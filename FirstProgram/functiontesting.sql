--------------------- SALES ASSIGNED ACCOUNTS SUMMARY REVIEW -------------------------
-- This SQL query retrieves a summary of sales assigned accounts, including inflow, outflow, fees, and balances.


WITH 
SalesAssignedAccounts AS (
    SELECT * 
    FROM bank78_onboarding_svc."SalesAssignedAccounts" sa 
    WHERE sa."SalesPersonCode" = 'SAL-0003' -- replace with actual sales_person_code
),
AccountHolders AS (
    SELECT
        saa."Email",
        saa."AccountHolder",
        CASE WHEN saa."AccountHolder" = 'Customer' THEN c."Id" ELSE NULL END AS "CustomerId",
        CASE WHEN saa."AccountHolder" = 'Business' THEN b."Id" ELSE NULL END AS "BusinessId"
    FROM SalesAssignedAccounts saa
    LEFT JOIN bank78_onboarding_svc."Customers" c 
        ON saa."AccountHolder" = 'Customer' AND c."UserName" = saa."Email"
    LEFT JOIN bank78_onboarding_svc."Businesses" b 
        ON saa."AccountHolder" = 'Business' AND b."Email" = saa."Email"
),
Accounts AS (
    SELECT 
        ah."Email",
        a."AccountNumber"
    FROM AccountHolders ah
    JOIN bank78_onboarding_svc."Accounts" a
        ON (ah."CustomerId" IS NOT NULL AND a."CustomerId" = ah."CustomerId")
        OR (ah."BusinessId" IS NOT NULL AND a."BusinessId" = ah."BusinessId")
),
InflowBreakdown AS (
    SELECT 
        acc."Email",
        SUM(pct."Amount"::NUMERIC) AS "TotalInflow"
    FROM bank78_nipinward_svc."PostCreditTransactions" pct
    JOIN Accounts acc ON acc."AccountNumber" = pct."BeneficiaryAccountNumber"
    WHERE pct."RequestDate" BETWEEN DATE '2024-01-01' AND DATE '2025-12-31' -- replace with actual dates
    GROUP BY acc."Email"
),
TransactionsBreakdown AS (
    SELECT 
        t."EmailAddress",
        SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."Amount"::NUMERIC ELSE 0 END) AS "TotalOutflow",
        SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."TransactionFee"::NUMERIC ELSE 0 END) AS "TotalFees",
        SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."TransactionFee"::NUMERIC * 0.93 ELSE 0 END) AS "TotalRevenue"
    FROM bank78_transaction_svc."Transactions" t
    WHERE t."DateCreated" BETWEEN DATE '2024-01-01' AND DATE '2024-12-31'
    AND t."EmailAddress" IN (
        SELECT "Email" FROM SalesAssignedAccounts
    )
    GROUP BY t."EmailAddress"
),
LatestBalances AS (
    SELECT 
        db."UserName",
        db."AccountHolder",
        db."TotalLedgerBalance",
        db."TotalAvailableBalance"
    FROM bank78_onboarding_svc."DailyBalances" db
    JOIN SalesAssignedAccounts sa
        ON db."UserName" = sa."Email"
        AND db."AccountHolder" = sa."AccountHolder"
)
SELECT
    sa."Email"::TEXT AS "Email",
    sa."AccountName"::TEXT AS "AccountName",
    sa."PhoneNumber"::TEXT AS "PhoneNumber",
    sa."AccountHolder"::TEXT AS "AccountHolder",
    COALESCE(ts."TotalOutflow", 0) AS "TotalOutflow",
    COALESCE(ib."TotalInflow", 0) AS "TotalInflow",
    COALESCE(ts."TotalFees", 0) AS "TotalFees",
    COALESCE(ts."TotalRevenue", 0) AS "TotalRevenue",
    COALESCE(lb."TotalLedgerBalance", 0) AS "TotalLedgerBalance",
    COALESCE(lb."TotalAvailableBalance", 0) AS "TotalAvailableBalance"
FROM SalesAssignedAccounts sa
LEFT JOIN TransactionsBreakdown ts 
    ON sa."Email" = ts."EmailAddress"
LEFT JOIN InflowBreakdown ib 
    ON sa."Email" = ib."Email"
LEFT JOIN LatestBalances lb 
    ON sa."Email" = lb."UserName"
    AND sa."AccountHolder" = lb."AccountHolder"
ORDER BY sa."Email"; -- or change to any preferred static ordering

------------------------- SALES PERSON SUMMARY REVIEW -------------------------
-- This SQL query aggregates sales data for assigned accounts, including inflow, outflow, fees, and balances.
-- It provides a summary of financial activities for each sales person, grouped by their assigned accounts.
-- The query includes the number of business and customer accounts, total inflow, outflow, fees, revenue, and balances.
-- The data is filtered for a specific date range and grouped by sales person code.
-- The query is designed to be run in a PostgreSQL environment with the specified schemas and tables.


WITH SalesAssignedAccounts AS (
    SELECT * 
    FROM bank78_onboarding_svc."SalesAssignedAccounts"
),
SalesAssigngmentCounts AS (
    SELECT 
        sac."SalesPersonCode",
        SUM(CASE WHEN sac."AccountHolder" = 'Business' THEN 1 ELSE 0 END) AS numberOfBusiness,
        SUM(CASE WHEN sac."AccountHolder" = 'Customer' THEN 1 ELSE 0 END) AS numberOfCustomers
    FROM bank78_onboarding_svc."SalesAssignedAccounts" sac
    GROUP BY sac."SalesPersonCode"
),
AccountHolders AS (
    SELECT
        saa."Email",
        saa."SalesPersonCode",
        saa."AccountHolder",
        CASE WHEN saa."AccountHolder" = 'Customer' THEN c."Id" ELSE NULL END AS "CustomerId",
        CASE WHEN saa."AccountHolder" = 'Business' THEN b."Id" ELSE NULL END AS "BusinessId"
    FROM SalesAssignedAccounts saa
    LEFT JOIN bank78_onboarding_svc."Customers" c 
        ON saa."AccountHolder" = 'Customer' AND c."UserName" = saa."Email"
    LEFT JOIN bank78_onboarding_svc."Businesses" b 
        ON saa."AccountHolder" = 'Business' AND b."Email" = saa."Email"
),
Accounts AS (
    SELECT 
        ah."SalesPersonCode",
        ah."Email",
        a."AccountNumber"
    FROM AccountHolders ah
    JOIN bank78_onboarding_svc."Accounts" a
        ON (ah."CustomerId" IS NOT NULL AND a."CustomerId" = ah."CustomerId")
        OR (ah."BusinessId" IS NOT NULL AND a."BusinessId" = ah."BusinessId")
),
InflowBreakdown AS (
    SELECT 
        acc."SalesPersonCode",
        SUM(pct."Amount"::numeric) AS TotalInflow
    FROM bank78_nipinward_svc."PostCreditTransactions" pct
    JOIN Accounts acc ON acc."AccountNumber" = pct."BeneficiaryAccountNumber"
    WHERE pct."RequestDate" BETWEEN '2024-01-01' AND '2024-12-31'  -- replace with your date range
    GROUP BY acc."SalesPersonCode"
),
TransactionsBreakdown AS (
    SELECT 
        t."EmailAddress",
        SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."Amount"::numeric ELSE 0 END) AS TotalOutflow,
        SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."TransactionFee"::numeric ELSE 0 END) AS TotalFees,
        SUM(
            CASE 
                WHEN t."TransactionType" = 'Outflow' THEN
                    CASE 
                        WHEN t."TransactionFee"::numeric = 10.75 THEN 10
                        WHEN t."TransactionFee"::numeric = 26.88 THEN 25
                        WHEN t."TransactionFee"::numeric = 53.75 THEN 50
                        ELSE t."TransactionFee"::numeric * 0.93
                    END
                ELSE 0
            END
        ) AS TotalRevenue,
        SUM(CASE WHEN t."TransactionType" = 'Inflow' THEN t."Amount"::numeric ELSE 0 END) AS TotalDeposit
    FROM bank78_transaction_svc."Transactions" t
    WHERE t."DateCreated" BETWEEN '2023-01-01' AND '2025-12-31'  -- replace with your date range
    AND t."EmailAddress" IN (
        SELECT "Email" 
        FROM SalesAssignedAccounts
    )
    GROUP BY t."EmailAddress"
),
LatestBalances AS (
    SELECT 
        db."UserName",
        db."AccountHolder",
        db."TotalLedgerBalance"::numeric AS "TotalLedgerBalance",
        db."TotalAvailableBalance"::numeric AS "TotalAvailableBalance"
    FROM bank78_onboarding_svc."DailyBalances" db
    JOIN SalesAssignedAccounts sa
        ON db."UserName" = sa."Email"
        AND db."AccountHolder" = sa."AccountHolder"
)
SELECT 
    sa."SalesPersonCode"::TEXT AS "SalesPersonCode",
    sa."AssignedTo"::TEXT AS "AssignedTo",
    COUNT(sa."AccountHolder")::INTEGER AS "totalNumberOfAccounts",
    COALESCE(SUM(ts.TotalOutflow), 0)::DECIMAL AS "totalOutflow",
    COALESCE(SUM(ib.TotalInflow), 0)::DECIMAL AS "totalInflow",
    COALESCE(SUM(ts.TotalFees), 0)::DECIMAL AS "totalFees",
    COALESCE(SUM(ts.TotalRevenue), 0)::DECIMAL AS "totalRevenue",
    COALESCE(sac.numberOfBusiness, 0)::INTEGER AS "numberOfBusiness",
    COALESCE(sac.numberOfCustomers, 0)::INTEGER AS "numberOfCustomers",
    COALESCE(SUM(lb."TotalLedgerBalance"), 0)::DECIMAL AS "totalLedgerBalance",
    COALESCE(SUM(lb."TotalAvailableBalance"), 0)::DECIMAL AS "totalAvailableBalance"
FROM SalesAssignedAccounts sa
LEFT JOIN TransactionsBreakdown ts 
    ON sa."Email" = ts."EmailAddress"
LEFT JOIN InflowBreakdown ib 
    ON sa."SalesPersonCode" = ib."SalesPersonCode"
LEFT JOIN SalesAssigngmentCounts sac 
    ON sa."SalesPersonCode" = sac."SalesPersonCode"
LEFT JOIN LatestBalances lb 
    ON sa."Email" = lb."UserName" AND sa."AccountHolder" = lb."AccountHolder"
GROUP BY sa."SalesPersonCode", sa."AssignedTo", sac.numberOfBusiness, sac.numberOfCustomers
ORDER BY "totalAvailableBalance" DESC;  -- or ASC, depending on desired order


