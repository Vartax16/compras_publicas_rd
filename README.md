# Compras públicas RD

Análisis de las **contrataciones públicas de República Dominicana (2024)** construido en Databricks: pipeline medallón (Bronze → Silver → Gold) sobre Unity Catalog, modelo estrella analítico, set de preguntas SQL, dashboard y hallazgos.

* **Fuente de datos:** API de compras públicas de RD, formato OCDS (Open Contracting Data Standard), archivo `dominican_republic_api_2024.jsonl.gz` (≈45,6 MB, 58.287 procesos).
* **Catálogo de Unity Catalog:** `compras_rd` (esquemas `bronze`, `silver`, `gold`).
* **Alcance:** 74.682 contratos, 57.162 adjudicaciones, 11.952 proveedores, 447 instituciones, 10 modalidades de compra. Montos dominantes en DOP (99,9% de los contratos).

---

## Preguntas de análisis

Cada pregunta tiene su query en la carpeta [`sql/`](sql/) y su desarrollo en el notebook [`04_analisis`](notebooks/04_analisis):

| Archivo | Pregunta |
| --- | --- |
| `q00_monedas.sql` | ¿En qué monedas se contrata y cómo se distribuye el gasto? |
| `q01_kpis_generales.sql` | ¿Cuál es el tamaño global del gasto (contratos, proveedores, instituciones, ticket promedio y mediano)? |
| `q02_gasto_mensual.sql` | ¿Cómo evoluciona el gasto mes a mes y qué estacionalidad presenta? |
| `q03_gasto_instituciones.sql` | ¿Qué instituciones gastan más y cuán concentrado está el gasto? |
| `q04a_pareto_proveedores.sql` | ¿Cuántos proveedores concentran el 80% del gasto (curva de Pareto)? |
| `q04b_top_proveedores.sql` | ¿Quiénes son los principales proveedores del Estado? |
| `q05_modalidades.sql` | ¿Cómo se distribuye el gasto y el número de contratos por modalidad de compra? |
| `q06_tiempos_adjudicacion.sql` | ¿Cuánto tarda la adjudicación según la modalidad? |
| `q07_mipymes_genero.sql` | ¿Qué participación tienen las MIPYMES y las mujeres empresarias en el gasto? |
| `q08_estimado_vs_contratado.sql` | ¿Se desvía el monto contratado respecto al monto estimado? |
| `q09a_alerta_un_oferente.sql` | ¿Qué instituciones adjudican de forma sistemática con un solo oferente? |
| `q09b_alerta_proveedor_dominante.sql` | ¿En qué instituciones un mismo proveedor concentra más del 50% del gasto? |

## Hallazgos clave (2024, montos en DOP)

1. **Tamaño del gasto:** 74.580 contratos válidos por **RD$ 147.665 millones**, otorgados a 7.846 proveedores por 400 instituciones. El ticket promedio es RD$ 1,98 M, pero el mediano es solo RD$ 162.250 — la distribución está muy sesgada por grandes obras.
2. **Estacionalidad:** julio y agosto concentran el 30% del gasto anual (agosto es el pico: RD$ 20.069 M, 17% del año); diciembre es el segundo pico (11%). Enero es el mes más bajo (0,7%).
3. **Concentración institucional:** las 3 primeras instituciones explican ~25% del gasto: Ministerio de la Vivienda, Hábitat y Edificaciones (RD$ 13.740 M, 9,3%), CAASD (RD$ 11.780 M) y PROMESE (RD$ 11.745 M).
4. **Pareto extremo de proveedores:** **274 de 7.846 proveedores (3,5%) concentran el 80% del gasto**. El mayor proveedor, Oscar A Renta Negron, SA, factura RD$ 7.602 M (5,2% del total); Malespin Constructora logró RD$ 5.395 M con solo 4 contratos.
5. **Modalidades asimétricas:** la Licitación Pública Nacional concentra el 49,6% del monto con apenas el 2,4% de los contratos; en el otro extremo, las Compras por Debajo del Umbral son el 50,9% de los contratos pero solo el 2,8% del monto.
6. **Tiempos de adjudicación:** mediana de 1 día en procesos `open`, 11 días en `direct` y 14 días en `selective` (p90 de 50 días). Se excluyeron 3 procesos con tiempos negativos y 5 sin fechas.
7. **MIPYMES y género:** micro (10,4%), small (20,6%) y medium (11,2%) suman ~42% del monto; large solo 5,9% (51,9% sin escala declarada). Empresas de propietarios hombres capturan el 80,3% del gasto frente a 19,7% de mujeres.
8. **Estimado vs. contratado:** la desviación total es baja (+1,4% en `open`, +1,8% en `direct`, +4,5% en `selective`) y la desviación mediana por proceso es 0: el gasto se ajusta bien a lo estimado.
9. **Alertas de competencia:** la Comisión de Defensa Comercial (98,2%), el Cuerpo de Bomberos de Santo Domingo Este (98,1%) y el Hospital Ciudad Juan Bosch (98,0%) adjudican con un solo oferente en casi todos sus procesos. En el Instituto para el Desarrollo del Suroeste, un único proveedor (Const E Inmobi SF, SRL) capta el 97,9% del gasto institucional; otros 19 casos superan el 50%.
10. **Monedas:** 74.596 contratos en DOP (RD$ 147.665 M), 79 en USD (USD 72,8 M) y 7 en EUR (EUR 120,2 M). Los agregados están particionados por moneda; este análisis usa DOP.

### Tarjetas de KPI (q01)

| Indicador | Valor |
| --- | --- |
| Contratos (DOP válidos) | 74.580 |
| Proveedores distintos | 7.846 |
| Instituciones | 400 |
| Gasto total | RD$ 147.665.326.218 |
| Ticket promedio | RD$ 1.979.959 |
| Ticket mediano | RD$ 162.250 |

### Top instituciones por gasto (q03)

| Institución | Contratos | Monto (RD$) | Participación |
| --- | --- | --- | --- |
| Ministerio de la Vivienda, Hábitat y Edificaciones | 235 | 13.739.715.342 | 9,30% |
| Corporación del Acueducto y Alcantarillado de Santo Domingo (CAASD) | 341 | 11.779.552.531 | 7,98% |
| Programa de Medicamentos Esenciales (PROMESE) | 408 | 11.745.109.192 | 7,95% |
| Ministerio de Educación | 813 | 5.859.809.700 | 3,97% |
| Dirección de Estrategia y Comunicación Gubernamental | 133 | 5.217.836.857 | 3,53% |

## Dashboard

El análisis interactivo está publicado en el dashboard **Compras públicas RD 2024**:

[**Compras públicas RD 2024**](https://dbc-a35aeac3-47ea.cloud.databricks.com/dashboardsv3/01f1da3c27b01e99a515b32042ad8b89/published?o=7474655540169566) *(abrir en Databricks)*
<img width="1632" height="744" alt="image" src="https://github.com/user-attachments/assets/df999eaf-d1cb-4cdb-9d9a-6296acddd78f" />



Incluye: KPIs generales, evolución mensual del gasto, top instituciones y proveedores, modalidades de compra, participación de MIPYMES y mujeres empresarias, y alertas de competencia (un solo oferente / proveedor dominante).

## Arquitectura del proyecto

```
compras_publicas_rd/
├── README.md
├── docs/
│   └── diccionario_datos.md      # Diccionario de datos completo (14 tablas)
├── notebooks/
│   ├── 01_bronze_ingesta         # JSON OCDS → Delta crudo + auditoría
│   ├── 02_silver_limpieza        # Aplanado, deduplicación por ocid, flags de calidad
│   ├── 03_gold_modelo            # Modelo estrella (dims, facts, agregados)
│   └── 04_analisis               # Preguntas de análisis y hallazgos (SQL)
├── sql/                           # Queries q00–q09b (una por pregunta)
└── dashboards/
    └── Compras públicas RD 2024.lvdash.json
```

Flujo de datos:

```
API compras RD (OCDS, JSONL.gz)
        │
        ▼
[Bronze] contratos_raw (esquema anidado original + _ingest_ts, _source_file)
        │  deduplicación por ocid, parseo de fechas, aplanado
        ▼
[Silver] procesos · adjudicaciones · contratos · proveedores
        │  modelo estrella + agregados precalculados
        ▼
[Gold]  dim_fecha · dim_institucion · dim_modalidad · dim_proveedor
        fact_contratos · fact_procesos
        agg_gasto_mensual · agg_gasto_institucion · agg_proveedores
        │
        ▼
[sql/]  q00–q09b  →  [04_analisis]  →  [Dashboard]
```

## Cómo reproducir

1. Ejecutar en orden los notebooks de [`notebooks/`](notebooks/): `01_bronze_ingesta` → `02_silver_limpieza` → `03_gold_modelo`.
2. Las preguntas de análisis están en [`notebooks/04_analisis`](notebooks/04_analisis) y en versión standalone en [`sql/`](sql/) (todas consultan `compras_rd.gold.*`).
3. Detalle de cada tabla y columna: [`docs/diccionario_datos.md`](docs/diccionario_datos.md).

## Reglas de calidad aplicadas

* Deduplicación por `ocid` conservando el registro más reciente (los 58.287 ocid resultaron únicos).
* `flag_monto_invalido` (monto nulo o ≤ 0): excluido de todas las sumas y agregados.
* `flag_fecha_incoherente` (inicio de contrato posterior al fin): marcado, no eliminado.
* Análisis de gasto restringido a moneda DOP para evitar mezclar unidades sin tipo de cambio.
* Cobertura de claves verificada: 100% de los contratos tiene proveedor, institución y fecha en sus dimensiones.

---

*Proyecto construido con Databricks (Unity Catalog, Delta Lake, PySpark y SQL). Noviembre 2026.*
