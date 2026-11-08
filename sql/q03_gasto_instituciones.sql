--Instituciones con mayot gasto
SELECT
  institucion, num_contratos,
  ROUND(monto_total)                                              AS monto_total,
  ROUND(monto_total / SUM(monto_total) OVER (), 4)                AS participacion,
  ROUND(SUM(monto_total) OVER (ORDER BY monto_total DESC)
        / SUM(monto_total) OVER (), 4)                            AS participacion_acumulada
FROM compras_rd.gold.agg_gasto_institucion
WHERE moneda = 'DOP'
ORDER BY monto_total DESC
LIMIT 15;