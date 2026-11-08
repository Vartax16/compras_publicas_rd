--Top 10 proveedores


SELECT
  p.nombre, p.escala, r.n_contratos,
  ROUND(r.m)                                          AS monto_total,
  ROUND(r.m / SUM(r.m) OVER (), 4)                    AS participacion
FROM (
  SELECT proveedor_id, COUNT(*) AS n_contratos, SUM(monto_contrato) AS m
  FROM compras_rd.gold.fact_contratos
  WHERE NOT flag_monto_invalido AND moneda = 'DOP' AND proveedor_id IS NOT NULL
  GROUP BY proveedor_id
) r
LEFT JOIN compras_rd.gold.dim_proveedor p ON r.proveedor_id = p.proveedor_id
ORDER BY r.m DESC
LIMIT 10;