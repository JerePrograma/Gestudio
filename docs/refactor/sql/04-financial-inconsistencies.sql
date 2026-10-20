WITH pago_aplicado AS (
    SELECT cargo_id, sum(importe_aplicado) AS importe
    FROM public.aplicaciones_pago WHERE estado = 'APLICADA' GROUP BY cargo_id
), credito_aplicado AS (
    SELECT coalesce(m.cargo_id, original.cargo_id) AS cargo_id,
           sum(CASE WHEN m.tipo = 'CONSUMO' THEN m.importe ELSE -m.importe END) AS importe
    FROM public.movimientos_credito m
    LEFT JOIN public.movimientos_credito original ON original.id = m.movimiento_revertido_id
    WHERE m.tipo = 'CONSUMO' OR (m.tipo = 'REVERSO' AND original.tipo = 'CONSUMO')
    GROUP BY coalesce(m.cargo_id, original.cargo_id)
), saldo_credito AS (
    SELECT m.alumno_id,
           sum(CASE
               WHEN m.tipo IN ('GENERACION','AJUSTE_CREDITO') THEN m.importe
               WHEN m.tipo IN ('CONSUMO','AJUSTE_DEBITO') THEN -m.importe
               WHEN original.tipo IN ('GENERACION','AJUSTE_CREDITO') THEN -m.importe
               ELSE m.importe END) AS saldo
    FROM public.movimientos_credito m
    LEFT JOIN public.movimientos_credito original ON original.id = m.movimiento_revertido_id
    GROUP BY m.alumno_id
)
SELECT 'FIN-CARGO-SALDO-NEGATIVO' AS rule_id, count(*) AS affected_count
FROM public.cargos c
LEFT JOIN pago_aplicado p ON p.cargo_id = c.id
LEFT JOIN credito_aplicado cr ON cr.cargo_id = c.id
WHERE c.importe_original - coalesce(p.importe, 0) - coalesce(cr.importe, 0) < 0
UNION ALL
SELECT 'FIN-PAGO-SOBREAPLICADO', count(*)
FROM (SELECT p.id FROM public.pagos p LEFT JOIN public.aplicaciones_pago a
      ON a.pago_id = p.id AND a.estado = 'APLICADA'
      GROUP BY p.id, p.monto_recibido HAVING coalesce(sum(a.importe_aplicado), 0) > p.monto_recibido) x
UNION ALL
SELECT 'FIN-CREDITO-NEGATIVO', count(*) FROM saldo_credito WHERE saldo < 0
UNION ALL
SELECT 'FIN-PAGO-SIN-CAJA', count(*)
FROM public.pagos p LEFT JOIN public.movimientos_caja m
  ON m.pago_id = p.id AND m.tipo = 'INGRESO_PAGO'
WHERE p.estado = 'REGISTRADO' AND m.id IS NULL
UNION ALL
SELECT 'FIN-STOCK-PROYECCION', count(*)
FROM public.stocks s LEFT JOIN (
    SELECT stock_id, sum(CASE
        WHEN tipo IN ('INGRESO','AJUSTE_POSITIVO','REVERSO') THEN cantidad
        WHEN tipo IN ('VENTA','AJUSTE_NEGATIVO') THEN -cantidad
        ELSE 0
    END) cantidad
    FROM public.movimientos_stock GROUP BY stock_id
) m ON m.stock_id = s.id
WHERE s.requiere_control_de_stock AND s.cantidad_actual <> coalesce(m.cantidad, 0)
ORDER BY rule_id;
