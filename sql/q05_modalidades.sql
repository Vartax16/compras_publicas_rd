SELECT
  COALESCE(m.modalidad, 'sin dato')        AS modalidad,
  COALESCE(m.modalidad_detalle, 'sin dato') AS detalle,
  COUNT(*)                                  AS contratos,
  ROUND(SUM(fc.monto_contrato))             AS monto_total,
  ROUND(SUM(fc.monto_contrato) / SUM(SUM(fc.monto_contrato)) OVER (), 4) AS pct_monto,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 4)                             AS pct_contratos
FROM compras_rd.gold.fact_contratos fc
LEFT JOIN compras_rd.gold.dim_modalidad m ON fc.modalidad_key = m.modalidad_key
WHERE NOT fc.flag_monto_invalido AND fc.moneda = 'DOP'
GROUP BY m.modalidad, m.modalidad_detalle
ORDER BY monto_total DESC;