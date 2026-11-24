-- =====================================================================
--  KYC Red-Flag Checker
--  Finds suspicious customer sign-ups using simple SQL.
--  All data is made up. Never use real customer data.
-- =====================================================================
-- STEP 1: Create a fresh database
DROP DATABASE IF EXISTS kyc_check;
CREATE DATABASE kyc_check;
USE kyc_check;

-- STEP 2: Create the two tables

-- Table 1: what the customer typed in the sign-up form
CREATE TABLE customers (
    customer_id  INT PRIMARY KEY,
    full_name    VARCHAR(100),
    dob          DATE,
    phone        VARCHAR(15),
    pan_number   VARCHAR(10),
    city         VARCHAR(50),
    kyc_status   VARCHAR(20)      -- APPROVED or PENDING
);

-- Table 2: what is printed on the documents they uploaded
CREATE TABLE kyc_documents (
    doc_id       INT PRIMARY KEY,
    customer_id  INT,
    doc_type     VARCHAR(20),     -- PAN or PASSPORT
    name_on_doc  VARCHAR(100),
    expiry_date  DATE,            -- empty for PAN (PAN never expires)
    uploaded_on  DATE,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- STEP 3: Add sample data (some problems are hidden on purpose)

INSERT INTO customers VALUES
(1,  'Aarav Sharma', '1994-03-12', '9876500001', 'ABCPS1234A', 'Pune',      'APPROVED'),
(2,  'Diya Patel',   '1998-07-21', '9876500002', 'ABCPP2345B', 'Ahmedabad', 'APPROVED'),
(3,  'Rohan Verma',  '1990-01-05', '9876500003', 'ABCPV3456C', 'Delhi',     'APPROVED'),
(4,  'Rahul Mehta',  '1992-08-08', '9876500004', 'ABCPM9999Z', 'Mumbai',    'APPROVED'),  -- same PAN as 5 and 6
(5,  'Rahul Mehra',  '1992-08-08', '9876500005', 'ABCPM9999Z', 'Mumbai',    'PENDING'),
(6,  'R Mehta',      '1992-08-08', '9876500006', 'ABCPM9999Z', 'Thane',     'PENDING'),
(7,  'Neha Gupta',   '1993-02-02', '9999911111', 'ABCPG1111K', 'Jaipur',    'APPROVED'),  -- same phone as 8
(8,  'Pooja Gupta',  '1994-06-15', '9999911111', 'ABCPG2222L', 'Jaipur',    'PENDING'),
(9,  'Vikram Rao',   '1991-12-01', '9876500009', 'ABCPR4444N', 'Hyderabad', 'APPROVED'),  -- name differs on PAN
(10, 'Arjun Das',    '2010-02-14', '9876500010', 'ABCPD6666Q', 'Kolkata',   'PENDING'),   -- under 18
(11, 'Farhan Khan',  '1987-03-03', '9876500011', 'ABCPK7777R', 'Lucknow',   'PENDING'),   -- expired passport
(12, 'Sneha Iyer',   '1996-11-30', '9876500012', 'ABCPI4567D', 'Chennai',   'APPROVED');

INSERT INTO kyc_documents VALUES
(101, 1,  'PAN',      'AARAV SHARMA', NULL,         '2026-10-01'),
(102, 2,  'PAN',      'DIYA PATEL',   NULL,         '2026-10-01'),
(103, 3,  'PAN',      'ROHAN VERMA',  NULL,         '2026-10-02'),
(104, 4,  'PAN',      'RAHUL MEHTA',  NULL,         '2026-10-05'),
(105, 5,  'PAN',      'RAHUL MEHRA',  NULL,         '2026-10-05'),
(106, 6,  'PAN',      'R MEHTA',      NULL,         '2026-10-05'),
(107, 7,  'PAN',      'NEHA GUPTA',   NULL,         '2026-10-06'),
(108, 8,  'PAN',      'POOJA GUPTA',  NULL,         '2026-10-07'),
(109, 9,  'PAN',      'VIKAS RAO',    NULL,         '2026-10-08'),
(110, 10, 'PAN',      'ARJUN DAS',    NULL,         '2026-10-09'),
(111, 11, 'PAN',      'FARHAN KHAN',  NULL,         '2026-10-10'),
(112, 11, 'PASSPORT', 'FARHAN KHAN',  '2025-06-30', '2026-10-10'),
(113, 12, 'PAN',      'SNEHA IYER',   NULL,         '2026-10-11');

-- Quick look at the data
SELECT * FROM customers;
SELECT * FROM kyc_documents;

-- =====================================================================
-- STEP 4: THE FIVE CHECKS  (run each one separately)
-- =====================================================================

-- Check 1: Same PAN used by more than one customer
SELECT pan_number, COUNT(*) AS number_of_accounts
FROM customers
GROUP BY pan_number
HAVING COUNT(*) > 1;

-- Check 2: Same phone number used by more than one customer
SELECT phone, COUNT(*) AS number_of_accounts
FROM customers
GROUP BY phone
HAVING COUNT(*) > 1;

-- Check 3: Name on the document does not match the name in the form
SELECT c.customer_id, c.full_name, d.name_on_doc
FROM customers c
JOIN kyc_documents d ON c.customer_id = d.customer_id
WHERE UPPER(c.full_name) <> d.name_on_doc;


-- Check 4: Customer is under 18
SELECT customer_id, full_name, dob,
       TIMESTAMPDIFF(YEAR, dob, CURDATE()) AS age
FROM customers
WHERE TIMESTAMPDIFF(YEAR, dob, CURDATE()) < 18;

-- Check 5: Document had already expired when it was uploaded
SELECT customer_id, doc_type, expiry_date, uploaded_on
FROM kyc_documents
WHERE expiry_date < uploaded_on;

-- =====================================================================
-- STEP 5: COMBINE ALL CHECKS INTO ONE RISK REPORT
-- =====================================================================
-- The CTE red_flags stacks the results of all five checks into one list
-- (UNION ALL = put lists one under another). Each flag carries points.
-- Then we add up points per customer and label them HIGH / MEDIUM / LOW.

CREATE VIEW risk_report AS
WITH red_flags AS (
    SELECT customer_id, 'Duplicate PAN' AS reason, 40 AS points
    FROM customers
    WHERE pan_number IN (SELECT pan_number FROM customers
                         GROUP BY pan_number HAVING COUNT(*) > 1)

    UNION ALL
    SELECT customer_id, 'Shared phone', 20
    FROM customers
    WHERE phone IN (SELECT phone FROM customers
                    GROUP BY phone HAVING COUNT(*) > 1)

    UNION ALL
    SELECT c.customer_id, 'Name mismatch', 30
    FROM customers c
    JOIN kyc_documents d ON c.customer_id = d.customer_id
    WHERE UPPER(c.full_name) <> d.name_on_doc

    UNION ALL
    SELECT customer_id, 'Under 18', 50
    FROM customers
    WHERE TIMESTAMPDIFF(YEAR, dob, CURDATE()) < 18

    UNION ALL
    SELECT customer_id, 'Expired document', 30
    FROM kyc_documents
    WHERE expiry_date < uploaded_on
)
SELECT c.customer_id,
       c.full_name,
       c.kyc_status,
       COUNT(f.reason)              AS total_flags,
       COALESCE(SUM(f.points), 0)   AS risk_points,
       CASE
           WHEN COALESCE(SUM(f.points), 0) >= 40 THEN 'HIGH'
           WHEN COALESCE(SUM(f.points), 0) >= 20 THEN 'MEDIUM'
           ELSE 'LOW'
       END                          AS risk_level,
       GROUP_CONCAT(f.reason)       AS reasons
FROM customers c
LEFT JOIN red_flags f ON c.customer_id = f.customer_id
GROUP BY c.customer_id, c.full_name, c.kyc_status;

-- The full report, riskiest first
SELECT * FROM risk_report ORDER BY risk_points DESC;
