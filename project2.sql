


---- 1.
SELECT
    YEAR(i.InvoiceDate) as year,
    SUM(il.ExtendedPrice) as incomePerYear,
    COUNT(DISTINCT MONTH(i.InvoiceDate)) as NumberOfDistinctMonths,
    SUM(il.ExtendedPrice) / COUNT(DISTINCT MONTH(i.InvoiceDate)) * 12 as yearlyLinearIncome,
    (SUM(il.ExtendedPrice) / COUNT(DISTINCT MONTH(i.InvoiceDate)) * 12 -
        LAG(SUM(il.ExtendedPrice) / COUNT(DISTINCT MONTH(i.InvoiceDate)) * 12)
        OVER (ORDER BY YEAR(i.InvoiceDate))) /
        NULLIF(LAG(SUM(il.ExtendedPrice) / COUNT(DISTINCT MONTH(i.InvoiceDate)) * 12)
        OVER (ORDER BY YEAR(i.InvoiceDate)), 0) * 100 as growthRate
FROM Sales.Invoices i
JOIN Sales.InvoiceLines il ON i.InvoiceID = il.InvoiceID
GROUP BY YEAR(i.InvoiceDate)
ORDER BY year;

-- 2.
WITH CustomerQuarterlyRanking AS (
    SELECT
        YEAR(i.InvoiceDate) as theYear,
        DATEPART(QUARTER, i.InvoiceDate) as theQuarter,
        c.CustomerName,
        SUM(il.ExtendedPrice - il.TaxAmount) as IncomePerYear,
        ROW_NUMBER() OVER (PARTITION BY YEAR(i.InvoiceDate),
            DATEPART(QUARTER, i.InvoiceDate)
            ORDER BY SUM(il.ExtendedPrice - il.TaxAmount) DESC) as DNR
    FROM Sales.Invoices i
    JOIN Sales.InvoiceLines il ON i.InvoiceID = il.InvoiceID
    JOIN Sales.Customers c ON i.CustomerID = c.CustomerID
    GROUP BY YEAR(i.InvoiceDate), DATEPART(QUARTER, i.InvoiceDate),
        c.CustomerName
)
SELECT *
FROM CustomerQuarterlyRanking
WHERE DNR <= 5
ORDER BY theYear, theQuarter, DNR;

--- 3.
SELECT TOP 10
    s.StockItemID,
    s.StockItemName,
    SUM(il.ExtendedPrice - il.TaxAmount) as TotalProfit
FROM Sales.InvoiceLines il
JOIN Warehouse.StockItems s ON il.StockItemID = s.StockItemID
GROUP BY s.StockItemID, s.StockItemName
ORDER BY TotalProfit DESC;

-- 4.
WITH LatestPrices AS (
    SELECT
        StockItemID,
        UnitPrice
    FROM (
        SELECT
            StockItemID,
            UnitPrice,
            ROW_NUMBER() OVER (PARTITION BY StockItemID ORDER BY LastEditedWhen DESC) as rn
        FROM Sales.InvoiceLines
    ) t
    WHERE rn = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY (s.RecommendedRetailPrice - lp.UnitPrice) DESC) as Rn,
    s.StockItemID,
    s.StockItemName,
    lp.UnitPrice as unitPrice,
    s.RecommendedRetailPrice as recommndedRetailPrice,
    (s.RecommendedRetailPrice - lp.UnitPrice) as nominalProductProfit,
    DENSE_RANK() OVER (ORDER BY (s.RecommendedRetailPrice - lp.UnitPrice) DESC) as DNR
FROM Warehouse.StockItems s
JOIN LatestPrices lp ON s.StockItemID = lp.StockItemID
WHERE s.ValidTo IS NULL OR s.ValidTo > GETDATE()
ORDER BY nominalProductProfit DESC;

-- 5.
SELECT
    CONCAT(s.SupplierID, ' - ', s.SupplierName) as supplierDetails,
    STRING_AGG(CONCAT(si.StockItemID, ' - ', si.StockItemName), ' / ') as productDetails
FROM Purchasing.Suppliers s
JOIN Warehouse.StockItems si ON s.SupplierID = si.SupplierID
GROUP BY s.SupplierID, s.SupplierName;

-- 6.
SELECT TOP 5
    c.CustomerID,
    ci.CityName,
    co.CountryName,
    co.Continent,
    co.Region,
    SUM(il.ExtendedPrice) as totalExtendedPrice
FROM Sales.Customers c
JOIN Sales.Invoices i ON c.CustomerID = i.CustomerID
JOIN Sales.InvoiceLines il ON i.InvoiceID = il.InvoiceID
JOIN Application.Cities ci ON c.DeliveryCityID = ci.CityID
JOIN Application.StateProvinces sp ON ci.StateProvinceID = sp.StateProvinceID
JOIN Application.Countries co ON sp.CountryID = co.CountryID
GROUP BY c.CustomerID, ci.CityName, co.CountryName, co.Continent, co.Region
ORDER BY totalExtendedPrice DESC;

-- 7.
WITH MonthlyOrders AS (
    SELECT
        YEAR(o.OrderDate) as orderYear,
        MONTH(o.OrderDate) as orderMonth,
        SUM(ol.Quantity) as monthlyTotal
    FROM Sales.Orders o
    JOIN Sales.OrderLines ol ON o.OrderID = ol.OrderID
    GROUP BY YEAR(o.OrderDate), MONTH(o.OrderDate)
)
SELECT
    orderYear,
    orderMonth,
    monthlyTotal,
    SUM(monthlyTotal) OVER (PARTITION BY orderYear
        ORDER BY orderMonth) as CumulativeTotal
FROM MonthlyOrders
ORDER BY orderYear, orderMonth;

-- 8.
SELECT
    MONTH(OrderDate) as orderMonth,
    SUM(CASE WHEN YEAR(OrderDate) = 2013 THEN 1 ELSE 0 END) as [2013],
    SUM(CASE WHEN YEAR(OrderDate) = 2014 THEN 1 ELSE 0 END) as [2014],
    SUM(CASE WHEN YEAR(OrderDate) = 2015 THEN 1 ELSE 0 END) as [2015],
    SUM(CASE WHEN YEAR(OrderDate) = 2016 THEN 1 ELSE 0 END) as [2016]
FROM Sales.Orders
GROUP BY MONTH(OrderDate)
ORDER BY orderMonth;


-- 9.
WITH OrderDates AS (
    SELECT
        c.CustomerID,
        c.CustomerName,
        o.OrderDate,
        LAG(o.OrderDate) OVER (PARTITION BY c.CustomerID ORDER BY o.OrderDate) as PreviousOrderDate,
        LEAD(o.OrderDate) OVER (PARTITION BY c.CustomerID ORDER BY o.OrderDate) as NextOrderDate
    FROM Sales.Customers c
    JOIN Sales.Orders o ON c.CustomerID = o.CustomerID
),
CustomerMetrics AS (
    SELECT
        CustomerID,
        CustomerName,
        MAX(OrderDate) as LastOrderDate,
        AVG(DATEDIFF(day, PreviousOrderDate, OrderDate)) as AvgDaysBetweenOrders
    FROM OrderDates
    WHERE PreviousOrderDate IS NOT NULL
    GROUP BY CustomerID, CustomerName
)
SELECT
    cm.CustomerID,
    cm.CustomerName,
    cm.LastOrderDate as orderDate,
    od.PreviousOrderDate as previousOrderDate,
    DATEDIFF(day, cm.LastOrderDate, GETDATE()) as daysSinceLastOrder,
    CAST(cm.AvgDaysBetweenOrders as int) as avgDaysBetweenOrders,
    CASE
        WHEN DATEDIFF(day, cm.LastOrderDate, GETDATE()) > 2 * cm.AvgDaysBetweenOrders
        THEN 'Potential Churn'
        ELSE 'Active'
    END as CustomerStatus
FROM CustomerMetrics cm
LEFT JOIN OrderDates od ON cm.CustomerID = od.CustomerID
    AND cm.LastOrderDate = od.OrderDate
WHERE cm.AvgDaysBetweenOrders IS NOT NULL
ORDER BY daysSinceLastOrder DESC;
-- 10.

WITH NormalizedCustomers AS (
    SELECT
        cc.CustomerCategoryID,
        cc.CustomerCategoryName,
        CASE
            WHEN c.CustomerName LIKE 'Wingtip%' THEN 'Wingtip Customer'
            WHEN c.CustomerName LIKE 'Tailspin%' THEN 'Tailspin Customer'
            ELSE c.CustomerName
        END as NormalizedName
    FROM Sales.CustomerCategories cc
    JOIN Sales.Customers c ON cc.CustomerCategoryID = c.CustomerCategoryID
),
CategoryStats AS (
    SELECT
        CustomerCategoryName,
        COUNT(DISTINCT NormalizedName) as customerCount,
        (SELECT COUNT(DISTINCT
            CASE
                WHEN CustomerName LIKE 'Wingtip%' THEN 'Wingtip Customer'
                WHEN CustomerName LIKE 'Tailspin%' THEN 'Tailspin Customer'
                ELSE CustomerName
            END)
        FROM Sales.Customers) as totalcustCount
    FROM NormalizedCustomers
    GROUP BY CustomerCategoryName
)
SELECT
    CustomerCategoryName,
    customerCount,
    totalcustCount,
    CAST((CAST(customerCount AS DECIMAL(10,2)) / CAST(totalcustCount AS DECIMAL(10,2)) * 100) AS DECIMAL(5,2)) as distributionFactor
FROM CategoryStats
ORDER BY distributionFactor DESC;
