-- Test script to verify South African ID anonymization
-- This script inserts a record with a South African ID number and displays the anonymized result

-- Set NOCOUNT to improve performance and reduce network traffic
SET NOCOUNT ON;

-- Print information about what we're doing
PRINT '===== Testing PII Anonymization =====';
PRINT 'Inserting a record with a South African ID...';

-- Store the raw text that contains a South African ID to insert
DECLARE @raw_text NVARCHAR(MAX);
SET @raw_text = 'Customer called to inquire about their account. Their South African ID is 9010205584087. They would like to update their contact details.';

PRINT 'Raw text with SA ID: ' + @raw_text;
PRINT '';

-- Execute the stored procedure to insert the comment (the trigger will handle anonymization)
PRINT 'Executing stored procedure usp_insert_comments...';
EXEC [dbo].[usp_insert_comments] @input_data = @raw_text;

-- Wait a moment to ensure processing completes
WAITFOR DELAY '00:00:01';

-- Query the table to display the inserted record with anonymized text
PRINT '';
PRINT 'Displaying anonymized record:';
SELECT TOP 1 id, comments, modified_date, api_modified_date 
FROM [dbo].[callcentre_comments] 
ORDER BY id DESC;

-- Print a summary of what happened
PRINT '';
PRINT '===== Test Summary =====';
PRINT 'If anonymization worked correctly, the South African ID should be replaced with ****** in the record above.';
PRINT 'Check that all other text remains intact.';
PRINT '======================';

-- End of script