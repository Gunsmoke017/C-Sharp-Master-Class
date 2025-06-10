--dev
CREATE OR REPLACE FUNCTION public.get_sales_assignment_summary_function_v3(
    sales_person_code text,
    start_date date DEFAULT NULL,
    end_date date DEFAULT CURRENT_DATE,
    sort_fields text[] DEFAULT NULL::text[],
    sort_dirs text[] DEFAULT NULL::text[]
)
RETURNS TABLE(
    email text,
    accountname text,
    phonenumber text,
    accountholder text,
    totaloutflow numeric,
    totalinflow numeric,
    totalfees numeric,
    totalrevenue numeric,
    totalledgerbalance numeric,
    totalavailablebalance numeric
)
LANGUAGE plpgsql
AS $function$
DECLARE
    order_clause TEXT := '';
    i INT;
BEGIN
    -- Dynamically build ORDER BY clause
    IF sort_fields IS NOT NULL AND sort_dirs IS NOT NULL THEN
        FOR i IN 1..array_length(sort_fields, 1) LOOP
            IF i > 1 THEN
                order_clause := order_clause || ', ';
            END IF;
            order_clause := order_clause || format(
                '%I %s',
                sort_fields[i],
                CASE WHEN sort_dirs[i] = 'A' THEN 'ASC' ELSE 'DESC' END
            );
        END LOOP;
    ELSE
        order_clause := 'sa."Email"';
    END IF;

    -- Set default start_date based on Transactions table if NULL
    IF start_date IS NULL THEN
        SELECT MIN("DateCreated") INTO start_date
        FROM bank78_transaction_svc."Transactions";

        IF start_date IS NULL THEN
            start_date := CURRENT_DATE - INTERVAL '365 days';
        END IF;
    END IF;

    RETURN QUERY EXECUTE format($f$
        WITH SalesAssignedAccounts AS (
            SELECT * 
            FROM bank78_onboarding_svc."SalesAssignedAccounts" sa 
            WHERE sa."SalesPersonCode" = $1
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
            WHERE pct."RequestDate" BETWEEN $2 AND $3
            GROUP BY acc."Email"
        ),
        TransactionsBreakdown AS (
            SELECT 
                t."EmailAddress",
                SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."Amount"::NUMERIC ELSE 0 END) AS "TotalOutflow",
                SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."TransactionFee"::NUMERIC ELSE 0 END) AS "TotalFees",
                SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."TransactionFee"::NUMERIC * 0.93 ELSE 0 END) AS "TotalRevenue"
            FROM bank78_transaction_svc."Transactions" t
            WHERE t."DateCreated" BETWEEN $2 AND $3
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
            sa."AccountName"::TEXT AS "accountName",
            sa."PhoneNumber"::TEXT AS "phoneNumber",
            sa."AccountHolder"::TEXT AS "accountHolder",
            COALESCE(ts."TotalOutflow", 0) AS "totalOutflow",
            COALESCE(ib."TotalInflow", 0) AS "totalInflow",
            COALESCE(ts."TotalFees", 0) AS "totalFees",
            COALESCE(ts."TotalRevenue", 0) AS "totalRevenue",
            COALESCE(lb."TotalLedgerBalance", 0) AS "totalLedgerBalance",
            COALESCE(lb."TotalAvailableBalance", 0) AS "totalAvailableBalance"
        FROM SalesAssignedAccounts sa
        LEFT JOIN TransactionsBreakdown ts 
            ON sa."Email" = ts."EmailAddress"
        LEFT JOIN InflowBreakdown ib 
            ON sa."Email" = ib."Email"
        LEFT JOIN LatestBalances lb 
            ON sa."Email" = lb."UserName"
            AND sa."AccountHolder" = lb."AccountHolder"
        ORDER BY %s
    $f$, order_clause)
    USING sales_person_code, start_date, end_date;
END;
$function$;


--prod
CREATE OR REPLACE FUNCTION public.get_sales_assignment_summary_function_v3(
    sales_person_code TEXT,
    start_date DATE,
    end_date DATE,
    sort_fields TEXT[] DEFAULT NULL::TEXT[],
    sort_dirs TEXT[] DEFAULT NULL::TEXT[]
)
RETURNS TABLE(
    email TEXT,
    accountname TEXT,
    phonenumber TEXT,
    accountholder TEXT,
    totaloutflow NUMERIC,
    totalinflow NUMERIC,
    totalfees NUMERIC,
    totalrevenue NUMERIC,
    totalledgerbalance NUMERIC,
    totalavailablebalance NUMERIC
)
LANGUAGE plpgsql
AS $function$
DECLARE
    order_clause TEXT := '';
    i INT;
BEGIN
    -- Dynamically build ORDER BY clause
    IF sort_fields IS NOT NULL AND sort_dirs IS NOT NULL THEN
        FOR i IN 1..array_length(sort_fields, 1) LOOP
            IF i > 1 THEN
                order_clause := order_clause || ', ';
            END IF;
            order_clause := order_clause || format(
                '%I %s',
                sort_fields[i],
                CASE WHEN sort_dirs[i] = 'A' THEN 'ASC' ELSE 'DESC' END
            );
        END LOOP;
    ELSE
        order_clause := 'sa."Email"';
    END IF;

    RETURN QUERY EXECUTE format($f$
        WITH SalesAssignedAccounts AS (
            SELECT * 
            FROM bank78_onboarding_svc."SalesAssignedAccounts" sa 
            WHERE sa."SalesPersonCode" = $1
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
            WHERE pct."RequestDate" BETWEEN $2 AND $3
            GROUP BY acc."Email"
        ),
        TransactionsBreakdown AS (
            SELECT 
                t."EmailAddress",
                SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."Amount"::NUMERIC ELSE 0 END) AS "TotalOutflow",
                SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."TransactionFee"::NUMERIC ELSE 0 END) AS "TotalFees",
                SUM(CASE WHEN t."TransactionType" = 'Outflow' THEN t."TransactionFee"::NUMERIC * 0.93 ELSE 0 END) AS "TotalRevenue"
            FROM bank78_transaction_svc."Transactions" t
            WHERE t."DateCreated" BETWEEN $2 AND $3
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
        ORDER BY %s
    $f$, order_clause)
    USING sales_person_code, start_date, end_date;
END;
$function$;
