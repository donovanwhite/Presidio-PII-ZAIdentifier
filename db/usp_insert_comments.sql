SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Check if procedure exists before creating
IF NOT EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_insert_comments')
BEGIN
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
    PRINT 'Procedure usp_insert_comments already exists. Use ALTER PROCEDURE to modify it.'
END
GO
