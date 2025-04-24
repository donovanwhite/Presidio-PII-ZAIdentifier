import logging
from fastapi import FastAPI, Request, HTTPException
from presidio_analyzer import AnalyzerEngine, PatternRecognizer, Pattern
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import OperatorConfig
from presidio_analyzer.predefined_recognizers import CreditCardRecognizer
from typing import Optional, List, Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# Custom Recognizer for South African ID
class ZaIdentityCardRecognizer(PatternRecognizer):
    PATTERNS = [
        Pattern(
            "South African ID Number (weak)",
            r"\b\d{13}\b",
            0.5,
        ),
    ]

    CONTEXT = [
        "id",
        "identity",
        "number",
        "sa id",
        "south african id",
        "identification",
    ]

    def __init__(
        self,
        patterns: Optional[List[Pattern]] = None,
        context: Optional[List[str]] = None,
        supported_language: str = "en",
        supported_entity: str = "ZA_ID",
    ):
        patterns = patterns if patterns else self.PATTERNS
        context = context if context else self.CONTEXT
        super().__init__(
            supported_entity=supported_entity,
            patterns=patterns,
            context=context,
            supported_language=supported_language,
        )

    def luhn_checksum(self, id_number: str) -> int:
        def digits_of(n: str) -> List[int]:
            return [int(d) for d in n]
        digits = digits_of(id_number)
        odd_digits = digits[-1::-2]
        even_digits = digits[-2::-2]
        checksum = sum(odd_digits)
        for d in even_digits:
            checksum += sum(digits_of(str(d * 2)))
        return checksum % 10

    def is_valid_sa_id(self, id_number: str) -> bool:
        cleaned_id = id_number.replace("-", "").replace(".", "")
        return self.luhn_checksum(cleaned_id) == 0

    def analyze(self, text: str, entities: List[str], nlp_artifacts: Any) -> List[Any]:
        results = super().analyze(text, entities, nlp_artifacts)
        filtered_results = []
        for result in results:
            id_number = text[result.start:result.end]
            if self.is_valid_sa_id(id_number):
                result.score = 1.0
                filtered_results.append(result)
        return filtered_results

# Initialize the engines
analyzer = AnalyzerEngine()
anonymizer = AnonymizerEngine()

# Create the recognizers
za_id_recognizer = ZaIdentityCardRecognizer()
cc_recognizer = CreditCardRecognizer()

analyzer.registry.add_recognizer(za_id_recognizer)
analyzer.registry.add_recognizer(cc_recognizer)

@app.post("/analyze")
async def analyze(request: Request) -> Dict[str, Any]:
    try:
        data = await request.json()
        text = data.get("text")
        if not text:
            raise HTTPException(status_code=400, detail="Text field is required")
        if len(text) > 8000:
            raise HTTPException(status_code=400, detail="Text cannot exceed 8000 characters")

        logger.info("Analyzing text for PII...")
        results = analyzer.analyze(text=text, entities=["ZA_ID", "CREDIT_CARD"], language="en")

        if not results:
            logger.info("No PII detected.")
            return {"anonymized_text": {"text": text}}

        # Anonymize the detected entities by replacing them
        anonymized_text = anonymizer.anonymize(text=text, analyzer_results=results, operators={
            "ZA_ID": OperatorConfig("replace", {"new_value": "******"}),
            "CREDIT_CARD": OperatorConfig("replace", {"new_value": "******"})
        })

        logger.info("PII anonymization complete.")
        return {"anonymized_text": anonymized_text}

    except Exception as e:
        logger.error(f"Error during analysis: {e}")
        raise HTTPException(status_code=500, detail=str(e))
