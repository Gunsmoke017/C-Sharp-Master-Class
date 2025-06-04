CREATE OR REPLACE FUNCTION public.get_sales_summary_function_v3(
    start_date date, 
    end_date date, 
    sort_fields text[], 
    sort_dirs text[]
)
RETURNS TABLE(
    salespersoncode text, 
    assignedto text, 
    totalnumberofaccounts integer, 
    totaloutflow numeric, 
    totalinflow numeric, 
    totalfees numeric, 
    totalrevenue numeric, 
    numberofbusiness integer, 
    numberofcustomers integer, 
    totalledgerbalance numeric, 
    totalavailablebalance numeric
)
LANGUAGE plpgsql
AS $function$
DECLARE
    order_clause TEXT := '';
    i INT;
BEGIN
    -- Build the ORDER BY clause dynamically
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
    END IF;

    -- Execute the query dynamically
    RETURN QUERY EXECUTE format($f$
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
            WHERE pct."RequestDate" BETWEEN $1 AND $2
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
            WHERE t."DateCreated" BETWEEN $1 AND $2
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
        ORDER BY %s
    $f$, order_clause)
    USING start_date, end_date;
END;
$function$;
