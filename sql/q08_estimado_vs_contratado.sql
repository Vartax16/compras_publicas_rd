SELECT
  COALESCE(m.modalidad, 'sin dato')                    AS modalidad,
  COUNT(*)                                             AS procesos,
  ROUND(SUM(fp.monto_estimado))                        AS estimado,
  ROUND(SUM(fp.monto_contratado))                      AS contratado,
  ROUND(SUM(fp.monto_contratado) / SUM(fp.monto_estimado) - 1, 4) AS desvio_total,
  ROUND(percentile_approx(fp.monto_contratado / fp.monto_estimado - 1, 0.5), 4) AS desvio_mediano
FROM compras_rd.gold.fact_procesos fp
LEFT JOIN compras_rd.gold.dim_modalidad m ON fp.modalidad_key = m.modalidad_key
WHERE fp.moneda = 'DOP'
  AND fp.monto_estimado > 0
  AND fp.monto_contratado > 0
GROUP BY m.modalidad
HAVING COUNT(*) >= 30
ORDER BY procesos DESC;