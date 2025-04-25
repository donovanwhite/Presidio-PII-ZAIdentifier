SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Check if trigger exists before creating
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_before_insert_pii')
BEGIN
    EXEC('
    CREATE TRIGGER [dbo].[trg_before_insert_pii]
    ON [dbo].[callcentre_comments]
    INSTEAD OF INSERT
    AS
    BEGIN
        DECLARE @input_data NVARCHAR(MAX);
        DECLARE @response NVARCHAR(MAX);
        DECLARE @anonymized_text NVARCHAR(MAX);

        SELECT @input_data = comments FROM inserted;

        -- Call the stored procedure with the correct parameters
        EXEC usp_call_rest_endpoint @input_data, @response OUTPUT;

        -- Log the response for debugging
        PRINT ''Response from REST endpoint: '' + @response;

        -- Parse the JSON response to extract the anonymized_text
        SELECT @anonymized_text = JSON_VALUE(@response, ''$.result.anonymized_text.text'');

        -- Check if the anonymized_text is not null
        IF @anonymized_text IS NOT NULL
        BEGIN
            INSERT INTO callcentre_comments (comments, modified_date, api_modified_date)
            SELECT @anonymized_text, modified_date, GETDATE() FROM inserted;
        END
        ELSE
        BEGIN
            -- Handle the case where the response is not valid
            RAISERROR(''Invalid response from REST endpoint'', 16, 1);
        END
    END
    ')
END
ELSE
BEGIN
    PRINT 'Trigger trg_before_insert_pii already exists. Use ALTER TRIGGER to modify it.'
END
GO
