-- Evolución mensual y estacionalidad
SELECT
  anio, mes, num_contratos,
  ROUND(monto_total)                                   AS monto_total,
  ROUND(monto_total / LAG(monto_total) OVER (ORDER BY anio, mes) - 1, 3) AS var_vs_mes_anterior,
  ROUND(monto_total / SUM(monto_total) OVER (PARTITION BY anio), 3)      AS peso_en_el_anio
FROM compras_rd.gold.agg_gasto_mensual
WHERE moneda = 'DOP'
ORDER BY anio, mes;

-------------------------------------------------------------------------------------------------
SELECT
  make_date(df.anio, df.mes, 1)  AS mes_fecha,
  di.institucion,
  ROUND(SUM(fc.monto_contrato))  AS monto_total
FROM compras_rd.gold.fact_contratos fc
LEFT JOIN compras_rd.gold.dim_fecha df       ON fc.fecha_key = df.fecha_key
LEFT JOIN compras_rd.gold.dim_institucion di ON fc.institucion_id = di.institucion_id
WHERE NOT fc.flag_monto_invalido AND fc.moneda = 'DOP'
GROUP BY make_date(df.anio, df.mes, 1), di.institucion
ORDER BY mes_fecha, di.institucion;