--proveedor dominante dentro de una institucion 
WITH x AS (
  SELECT
    fc.institucion_id, fc.proveedor_id,
    COUNT(*)                   AS n,
    SUM(fc.monto_contrato)     AS m
  FROM compras_rd.gold.fact_contratos fc
  WHERE NOT fc.flag_monto_invalido AND fc.moneda = 'DOP'
    AND fc.proveedor_id IS NOT NULL
  GROUP BY fc.institucion_id, fc.proveedor_id
),
y AS (
  SELECT *,
         m / SUM(m) OVER (PARTITION BY institucion_id)       AS participacion,
         SUM(n) OVER (PARTITION BY institucion_id)           AS contratos_institucion,
         ROW_NUMBER() OVER (PARTITION BY institucion_id ORDER BY m DESC) AS rk
  FROM x
)
SELECT
  di.institucion, p.nombre AS proveedor_dominante,
  y.contratos_institucion, ROUND(y.m) AS monto, ROUND(y.participacion, 3) AS participacion
FROM y
LEFT JOIN compras_rd.gold.dim_institucion di ON y.institucion_id = di.institucion_id
LEFT JOIN compras_rd.gold.dim_proveedor p ON y.proveedor_id = p.proveedor_id
WHERE y.rk = 1 AND y.participacion >= 0.5 AND y.contratos_institucion >= 20
ORDER BY y.participacion DESC
LIMIT 20;