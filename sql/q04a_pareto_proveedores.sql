--¿Cuántos proveedores explican el 80% del monto? 
WITH v AS (
  SELECT proveedor_id, SUM(monto_contrato) AS m
  FROM compras_rd.gold.fact_contratos
  WHERE NOT flag_monto_invalido AND moneda = 'DOP' AND proveedor_id IS NOT NULL
  GROUP BY proveedor_id
),
r AS (
  SELECT m,
         m / SUM(m) OVER ()                                AS part,
         SUM(m) OVER (ORDER BY m DESC) / SUM(m) OVER ()    AS acum
  FROM v
)
SELECT
  COUNT(*)                                                       AS total_proveedores,
  SUM(CASE WHEN acum - part < 0.8 THEN 1 ELSE 0 END)             AS proveedores_para_80pct,
  ROUND(100.0 * SUM(CASE WHEN acum - part < 0.8 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_de_proveedores
FROM r;