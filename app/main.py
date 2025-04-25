import logging
import os
from fastapi import FastAPI, Request, HTTPException
from presidio_analyzer import AnalyzerEngine, PatternRecognizer, Pattern
from presidio_anonymizer import AnonymizerEngine
from presidio_anonymizer.entities import OperatorConfig
from presidio_analyzer.predefined_recognizers import CreditCardRecognizer
from typing import Optional, List, Dict, Any
from tenacity import retry, stop_after_attempt, wait_exponential
from opencensus.ext.azure.log_exporter import AzureLogHandler
from opencensus.ext.azure.trace_exporter import AzureExporter
from opencensus.trace.samplers import ProbabilitySampler
from opencensus.trace.tracer import Tracer

# Configure logging with Azure App Insights if connection string is available
appinsights_connection_string = os.environ.get('APPLICATIONINSIGHTS_CONNECTION_STRING')
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Add console handler
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
console_handler.setFormatter(console_formatter)
logger.addHandler(console_handler)

# Configure Azure App Insights if available
if appinsights_connection_string:
    logger.info("Application Insights enabled")
    azure_handler = AzureLogHandler(connection_string=appinsights_connection_string)
    azure_handler.setFormatter(console_formatter)
    logger.addHandler(azure_handler)
    tracer = Tracer(
        exporter=AzureExporter(connection_string=appinsights_connection_string),
        sampler=ProbabilitySampler(1.0),
    )
else:
    logger.info("Application Insights not configured - using console logging only")
    tracer = None

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

# Initialize the engines with retry logic
@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def initialize_analyzer():
    logger.info("Initializing Presidio Analyzer engine")
    return AnalyzerEngine()

@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
def initialize_anonymizer():
    logger.info("Initializing Presidio Anonymizer engine")
    return AnonymizerEngine()

# Initialize with retry logic
try:
    analyzer = initialize_analyzer()
    anonymizer = initialize_anonymizer()
    
    # Create the recognizers
    za_id_recognizer = ZaIdentityCardRecognizer()
    cc_recognizer = CreditCardRecognizer()
    
    analyzer.registry.add_recognizer(za_id_recognizer)
    analyzer.registry.add_recognizer(cc_recognizer)
    
    logger.info("Presidio engines initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Presidio engines: {e}")
    raise

@app.get("/health")
async def health_check() -> Dict[str, str]:
    """Health check endpoint for container health monitoring"""
    try:
        # Verify that analyzer and anonymizer are initialized
        if analyzer and anonymizer:
            logger.debug("Health check succeeded")
            return {"status": "healthy"}
        else:
            logger.error("Health check failed: analyzer or anonymizer not initialized")
            return {"status": "unhealthy", "error": "Components not initialized"}
    except Exception as e:
        logger.error(f"Health check failed with error: {e}")
        return {"status": "unhealthy", "error": str(e)}

@app.post("/analyze")
async def analyze(request: Request) -> Dict[str, Any]:
    try:
        # Create a span for tracing the request if App Insights is configured
        if tracer:
            with tracer.span(name="analyze_text"):
                return await _analyze_implementation(request)
        else:
            return await _analyze_implementation(request)
    except Exception as e:
        logger.error(f"Error during analysis: {e}")
        raise HTTPException(status_code=500, detail=str(e))

async def _analyze_implementation(request: Request) -> Dict[str, Any]:
    try:
        data = await request.json()
        text = data.get("text")
        if not text:
            logger.warning("Request missing required 'text' field")
            raise HTTPException(status_code=400, detail="Text field is required")
        if len(text) > 8000:
            logger.warning(f"Text exceeds maximum length: {len(text)} characters")
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
        logger.error(f"Error during _analyze_implementation: {e}")
        raise
