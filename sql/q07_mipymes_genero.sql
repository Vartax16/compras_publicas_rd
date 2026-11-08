
SELECT
  COALESCE(p.genero, 'sin dato')            AS genero,
  COUNT(*)                                  AS contratos,
  ROUND(SUM(fc.monto_contrato))             AS monto_total,
  ROUND(SUM(fc.monto_contrato) / SUM(SUM(fc.monto_contrato)) OVER (), 4) AS pct_monto
FROM compras_rd.gold.fact_contratos fc
LEFT JOIN compras_rd.gold.dim_proveedor p ON fc.proveedor_id = p.proveedor_id
WHERE NOT fc.flag_monto_invalido AND fc.moneda = 'DOP'
GROUP BY p.genero
ORDER BY monto_total DESC;
----------------------------------------------------------------------------------------
SELECT
  COALESCE(p.genero, 'sin dato')            AS genero,
  COUNT(*)                                  AS contratos,
  ROUND(SUM(fc.monto_contrato))             AS monto_total,
  ROUND(SUM(fc.monto_contrato) / SUM(SUM(fc.monto_contrato)) OVER (), 4) AS pct_monto
FROM compras_rd.gold.fact_contratos fc
LEFT JOIN compras_rd.gold.dim_proveedor p ON fc.proveedor_id = p.proveedor_id
WHERE NOT fc.flag_monto_invalido AND fc.moneda = 'DOP'
GROUP BY p.genero
ORDER BY monto_total DESC;