-- SQL script to verify if stored procedures and triggers exist
-- This will output information about which database objects are missing

SET NOCOUNT ON;
PRINT '====== Database Object Verification ======';

-- Check for the stored procedures
IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_insert_comments')
    PRINT 'usp_insert_comments: ✓ Found';
ELSE
    PRINT 'usp_insert_comments: ✗ NOT FOUND';

IF EXISTS (SELECT * FROM sys.procedures WHERE name = 'usp_call_rest_endpoint')
    PRINT 'usp_call_rest_endpoint: ✓ Found';
ELSE
    PRINT 'usp_call_rest_endpoint: ✗ NOT FOUND';

-- Check for the trigger
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_before_insert_pii')
    PRINT 'trg_before_insert_pii: ✓ Found';
ELSE
    PRINT 'trg_before_insert_pii: ✗ NOT FOUND';

-- Check for required tables
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'callcentre_comments')
    PRINT 'callcentre_comments table: ✓ Found';
ELSE
    PRINT 'callcentre_comments table: ✗ NOT FOUND';

IF EXISTS (SELECT * FROM sys.tables WHERE name = 'callcentre_comments_cog')
    PRINT 'callcentre_comments_cog table: ✓ Found';
ELSE
    PRINT 'callcentre_comments_cog table: ✗ NOT FOUND';

-- Print details about existing procedures for diagnosis
PRINT '====== Stored Procedures List ======';
SELECT name FROM sys.procedures;

-- Print details about existing triggers for diagnosis
PRINT '====== Triggers List ======';
SELECT name FROM sys.triggers;

PRINT '====== Verification Complete ======';