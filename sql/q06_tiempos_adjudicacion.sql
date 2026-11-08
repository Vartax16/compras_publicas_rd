SELECT
  COALESCE(m.modalidad, 'sin dato') AS modalidad,
  COUNT(*)                                            AS procesos,
  ROUND(AVG(fp.dias_hasta_adjudicacion), 1)           AS dias_promedio,
  percentile_approx(fp.dias_hasta_adjudicacion, 0.5)  AS dias_mediana,
  percentile_approx(fp.dias_hasta_adjudicacion, 0.9)  AS dias_p90
FROM compras_rd.gold.fact_procesos fp
LEFT JOIN compras_rd.gold.dim_modalidad m ON fp.modalidad_key = m.modalidad_key
WHERE fp.dias_hasta_adjudicacion >= 0
GROUP BY m.modalidad
HAVING COUNT(*) >= 30
ORDER BY dias_mediana DESC;

SELECT
  SUM(CASE WHEN dias_hasta_adjudicacion < 0 THEN 1 ELSE 0 END) AS tiempos_negativos,
  SUM(CASE WHEN dias_hasta_adjudicacion IS NULL THEN 1 ELSE 0 END) AS sin_fechas,
  COUNT(*) AS total
FROM compras_rd.gold.fact_procesos;