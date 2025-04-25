-- Combined SQL deployment script for stored procedures and triggers
-- This script will create all necessary database objects if they don't exist

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- First check if stored procedure exists, then create it
IF NOT EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_call_rest_endpoint')
BEGIN
    PRINT 'Creating stored procedure usp_call_rest_endpoint...'
    EXEC('
    CREATE PROCEDURE [dbo].[usp_call_rest_endpoint]
        @input_data NVARCHAR(MAX),
        @response NVARCHAR(MAX) OUTPUT
    AS
    BEGIN
        DECLARE @url NVARCHAR(MAX) = ''https://presidiopii.azurewebsites.net/analyze'';
        DECLARE @headers NVARCHAR(MAX) = ''{"Content-Type": "application/json"}'';
        DECLARE @payload NVARCHAR(MAX) = ''{"text": "'' + @input_data + ''"}'';

        EXEC sp_invoke_external_rest_endpoint
            @url = @url,
            @method = ''POST'',
            @headers = @headers,
            @payload = @payload,
            @response = @response OUTPUT;
    END
    ')
END
ELSE
BEGIN
    PRINT 'Updating stored procedure usp_call_rest_endpoint...'
    EXEC('
    ALTER PROCEDURE [dbo].[usp_call_rest_endpoint]
        @input_data NVARCHAR(MAX),
        @response NVARCHAR(MAX) OUTPUT
    AS
    BEGIN
        DECLARE @url NVARCHAR(MAX) = ''https://presidiopii.azurewebsites.net/analyze'';
        DECLARE @headers NVARCHAR(MAX) = ''{"Content-Type": "application/json"}'';
        DECLARE @payload NVARCHAR(MAX) = ''{"text": "'' + @input_data + ''"}'';

        EXEC sp_invoke_external_rest_endpoint
            @url = @url,
            @method = ''POST'',
            @headers = @headers,
            @payload = @payload,
            @response = @response OUTPUT;
    END
    ')
END
GO

-- Check if stored procedure exists, then create it
IF NOT EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_insert_comments')
BEGIN
    PRINT 'Creating stored procedure usp_insert_comments...'
    EXEC('
    CREATE PROCEDURE [dbo].[usp_insert_comments]
        @input_data NVARCHAR(MAX)
    AS
    BEGIN
    SET NOCOUNT ON
        INSERT INTO [dbo].[callcentre_comments] (comments, modified_date, api_modified_date)
        VALUES (@input_data, GETDATE(), NULL);
    END
    ')
END
ELSE
BEGIN
    PRINT 'Updating stored procedure usp_insert_comments...'
    EXEC('
    ALTER PROCEDURE [dbo].[usp_insert_comments]
        @input_data NVARCHAR(MAX)
    AS
    BEGIN
    SET NOCOUNT ON
        INSERT INTO [dbo].[callcentre_comments] (comments, modified_date, api_modified_date)
        VALUES (@input_data, GETDATE(), NULL);
    END
    ')
END
GO

-- Check if trigger exists, then create it
IF NOT EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_before_insert_pii')
BEGIN
    PRINT 'Creating trigger trg_before_insert_pii...'
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
    PRINT 'Updating trigger trg_before_insert_pii...'
    EXEC('
    ALTER TRIGGER [dbo].[trg_before_insert_pii]
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
GO

PRINT 'All objects have been deployed successfully!'