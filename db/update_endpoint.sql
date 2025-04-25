-- SQL Template to update the endpoint URL in the usp_call_rest_endpoint stored procedure
-- This will be used to configure the stored procedure with the correct Container App URL
-- The https://presidio-pii-app.orangehill-9ef8c1e0.northeurope.azurecontainerapps.io/analyze placeholder will be replaced during deployment

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Check if procedure exists before creating or updating
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_call_rest_endpoint')
BEGIN
    -- Update existing stored procedure with the new endpoint URL
    DROP PROCEDURE [dbo].[usp_call_rest_endpoint]
END
GO

-- Create the stored procedure with the new endpoint URL
CREATE PROCEDURE [dbo].[usp_call_rest_endpoint]
    @input_data NVARCHAR(MAX),
    @response NVARCHAR(MAX) OUTPUT
AS
BEGIN
    -- The endpoint URL will be replaced during deployment
    DECLARE @url NVARCHAR(MAX) = 'https://presidio-pii-app.orangehill-9ef8c1e0.northeurope.azurecontainerapps.io/analyze';
    DECLARE @headers NVARCHAR(MAX) = '{"Content-Type": "application/json"}';
    DECLARE @payload NVARCHAR(MAX) = '{"text": "' + @input_data + '"}';

    -- Call the external REST endpoint
    EXEC sp_invoke_external_rest_endpoint
        @url = @url,
        @method = 'POST',
        @headers = @headers,
        @payload = @payload,
        @response = @response OUTPUT;
END
GO

-- Print confirmation message
PRINT 'Stored procedure created/updated with endpoint: https://presidio-pii-app.orangehill-9ef8c1e0.northeurope.azurecontainerapps.io/analyze';
GO