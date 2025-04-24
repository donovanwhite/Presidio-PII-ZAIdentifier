-- Insert dummy data with South African ID numbers into callcentre_comments table
INSERT INTO [dbo].[callcentre_comments] ([comments], [modified_date])
VALUES 
    ('Customer called about their account. Their South African ID is 8001015009087.', GETDATE()),
    ('Customer requested information about their policy. ID number: 9202204720082', GETDATE()),
    ('Caller mentioned having issues with online access. South African ID Number: 7608125077083', GETDATE()),
    ('New account setup for customer. ID: 8305145800089', GETDATE()),
    ('Policy change requested by customer with South African ID 6411125173081', GETDATE());

-- Insert dummy data with South African ID numbers into callcentre_comments_cog table
INSERT INTO [dbo].[callcentre_comments_cog] ([comments], [modified_date])
VALUES 
    ('Incoming call from customer with ID 9712155803084 regarding account access', GETDATE()),
    ('Customer complaint about billing issue. South African ID: 8107235069082', GETDATE()),
    ('New policy setup. Customer ID number: 9010205584087', GETDATE()),
    ('Account verification completed for South African ID 8503125049088', GETDATE()),
    ('Customer with ID 7705115046082 requested password reset', GETDATE());