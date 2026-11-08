SELECT moneda, COUNT(*) AS contratos, ROUND(SUM(monto_contrato)) AS monto
FROM compras_rd.gold.fact_contratos
GROUP BY moneda
ORDER BY contratos DESC;