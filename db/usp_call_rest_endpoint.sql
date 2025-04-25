SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Check if procedure exists before creating
IF NOT EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_call_rest_endpoint')
BEGIN
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
    PRINT 'Procedure usp_call_rest_endpoint already exists. Use ALTER PROCEDURE to modify it.'
END
GO
