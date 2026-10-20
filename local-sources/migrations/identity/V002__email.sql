ALTER TABLE accounts ADD COLUMN email TEXT;
UPDATE accounts SET email = 'demo@example.invalid' WHERE id = 1;
