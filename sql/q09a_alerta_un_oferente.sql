--instituciones con muchos procesos adjudicados con un solo oferente
SELECT
  di.institucion,
  COUNT(*)                                                     AS procesos_con_contrato,
  SUM(CASE WHEN fp.num_oferentes = 1 THEN 1 ELSE 0 END)        AS un_solo_oferente,
  ROUND(AVG(CASE WHEN fp.num_oferentes = 1 THEN 1.0 ELSE 0.0 END), 3) AS pct_un_oferente
FROM compras_rd.gold.fact_procesos fp
LEFT JOIN compras_rd.gold.dim_institucion di ON fp.institucion_id = di.institucion_id
WHERE fp.num_contratos > 0 AND fp.num_oferentes IS NOT NULL
GROUP BY di.institucion
HAVING COUNT(*) >= 30
ORDER BY pct_un_oferente DESC
LIMIT 15;