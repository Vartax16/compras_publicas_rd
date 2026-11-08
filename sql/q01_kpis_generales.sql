SELECT
  COUNT(*)                                  AS contratos,
  COUNT(DISTINCT proveedor_id)              AS proveedores,
  COUNT(DISTINCT institucion_id)            AS instituciones,
  ROUND(SUM(monto_contrato))                AS monto_total,
  ROUND(AVG(monto_contrato))                AS ticket_promedio,
  ROUND(percentile_approx(monto_contrato, 0.5)) AS ticket_mediano
FROM compras_rd.gold.fact_contratos
WHERE NOT flag_monto_invalido
  AND moneda = 'DOP';