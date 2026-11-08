# Diccionario de Datos — Compras Públicas RD

**Proyecto:** Análisis de las contrataciones públicas de República Dominicana (año 2024) en Databricks.

**Fuente de datos:** API de compras públicas de RD, exportada en formato OCDS (Open Contracting Data Standard) al archivo `/Volumes/compras_rd/bronze/raw_files/dominican_republic_api_2024.jsonl.gz` (≈45,6 MB comprimido).

**Catálogo de Unity Catalog:** `compras_rd`, con arquitectura medallón (Bronze → Silver → Gold) construida en los notebooks `01_bronze_ingesta`, `02_silver_limpieza` y `03_gold_modelo`.

| Capa | Tabla | Filas |
| --- | --- | --- |
| Bronze | `contratos_raw` | 58.287 |
| Silver | `procesos` | 58.287 |
| Silver | `adjudicaciones` | 57.162 |
| Silver | `contratos` | 74.682 |
| Silver | `proveedores` | 11.952 |
| Gold | `dim_fecha` | 1.826 |
| Gold | `dim_institucion` | 447 |
| Gold | `dim_modalidad` | 10 |
| Gold | `dim_proveedor` | 11.952 |
| Gold | `fact_contratos` | 74.682 |
| Gold | `fact_procesos` | 58.287 |
| Gold | `agg_gasto_mensual` | 50 |
| Gold | `agg_gasto_institucion` | 418 |
| Gold | `agg_proveedores` | 7.900 |

---

## 1. Bronze — `compras_rd.bronze.contratos_raw`

Ingesta cruda del JSON OCDS, un registro por proceso de contratación (`ocid`), sin transformaciones. Se conserva el esquema anidado original. Se agregan dos columnas técnicas de auditoría:

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `ocid` | string | Identificador único del proceso de contratación (clave OCDS) |
| `id` | string | Identificador del release OCDS |
| `date` | string | Fecha de publicación del release (texto ISO) |
| `tag` | array&lt;string&gt; | Etiquetas del release (p. ej. `tender`, `award`, `contract`) |
| `initiationType` | string | Tipo de iniciación (normalmente `tender`) |
| `language` | string | Idioma del registro |
| `parties` | array&lt;struct&gt; | Participantes del proceso: id, nombre, roles (`buyer`, `supplier`, `procuringEntity`…), RNC (`identifier.id`), dirección, contacto, y en `details` la escala (`scale`) y género (`gender`) |
| `tender` | struct | Licitación: id, título, entidad compradora (`procuringEntity`), modalidad (`procurementMethod` + `procurementMethodDetails`), categoría (`mainProcurementCategory`), estado (`status`), valor estimado (`value.amount`/`value.currency`), número de oferentes (`numberOfTenderers`), periodos de oferta (`tenderPeriod`) y adjudicación (`awardPeriod`) |
| `awards` | array&lt;struct&gt; | Adjudicaciones: id, fecha, estado, proveedores (`suppliers`) e ítems adjudicados (cantidad × valor unitario) |
| `contracts` | array&lt;struct&gt; | Contratos: id, `awardID`, estado, título, valor, y período (`period.startDate`/`endDate`) |
| `bids` | struct | Ofertas recibidas (`details`): fecha, estado, oferentes (`tenderers`) y valor |
| `planning` | struct | Planeación: presupuesto (`budget.amount`) y documentos |
| `_ingest_ts` | timestamp | Fecha y hora de la ingesta (añadida en el notebook) |
| `_source_file` | string | Ruta del archivo fuente de la ingesta (añadida en el notebook) |

---

## 2. Silver — `compras_rd.silver.*`

Los datos crudos se aplanan, se parsean las fechas con `try_to_timestamp` y se deduplican por `ocid` (se conserva el registro con fecha más reciente; en la práctica los 58.287 `ocid` son únicos). Una tabla por entidad del proceso de compra.

### 2.1 `silver.procesos` — un proceso de licitación (1 fila = 1 ocid)

| Columna | Tipo | Descripción | Origen OCDS |
| --- | --- | --- | --- |
| `ocid` | string | Identificador del proceso | `ocid` |
| `fecha_publicacion` | timestamp | Fecha de publicación del proceso | `date` |
| `tender_id` | string | Identificador de la licitación | `tender.id` |
| `titulo` | string | Título del proceso | `tender.title` |
| `institucion_id` | string | ID de la institución compradora | `tender.procuringEntity.id` |
| `institucion` | string | Nombre de la institución compradora (recortado de espacios) | `tender.procuringEntity.name` |
| `modalidad` | string | Modalidad genérica: `open`, `direct`, `selective` | `tender.procurementMethod` |
| `modalidad_detalle` | string | Modalidad específica: Compras por Debajo del Umbral, Contratación Menor, Comparación de Precios, Procesos de Excepción, Licitación Pública Nacional, Subasta Inversa, etc. | `tender.procurementMethodDetails` |
| `categoria` | string | Categoría principal (bienes, obras, servicios) | `tender.mainProcurementCategory` |
| `estado` | string | Estado de la licitación (mayoría `open`) | `tender.status` |
| `monto_estimado` | double | Valor estimado de la licitación | `tender.value.amount` |
| `moneda` | string | Moneda del monto estimado (`DOP`, `USD`, `EUR`) | `tender.value.currency` |
| `num_oferentes` | bigint | Número de oferentes que participaron | `tender.numberOfTenderers` |
| `inicio_oferta` | timestamp | Inicio del período de recepción de ofertas | `tender.tenderPeriod.startDate` |
| `fin_oferta` | timestamp | Cierre del período de ofertas | `tender.tenderPeriod.endDate` |
| `inicio_adjudicacion` | timestamp | Inicio del período de adjudicación | `tender.awardPeriod.startDate` |
| `fin_adjudicacion` | timestamp | Fin del período de adjudicación | `tender.awardPeriod.endDate` |
| `presupuesto` | double | Monto presupuestado en la planeación | `planning.budget.amount.amount` |
| `anio` | int | Año de `fecha_publicacion` | derivado |
| `mes` | int | Mes de `fecha_publicacion` (1-12) | derivado |
| `flag_monto_invalido` | boolean | `true` si `monto_estimado` es nulo o ≤ 0 | derivado |

### 2.2 `silver.adjudicaciones` — una fila por adjudicación

| Columna | Tipo | Descripción | Origen OCDS |
| --- | --- | --- | --- |
| `ocid` | string | Proceso al que pertenece la adjudicación | `ocid` |
| `award_id` | string | Identificador de la adjudicación | `awards.id` |
| `fecha_adjudicacion` | timestamp | Fecha de la adjudicación | `awards.date` |
| `estado_adjudicacion` | string | Estado (`active`, …) | `awards.status` |
| `num_proveedores` | int | Número de proveedores adjudicados | `size(awards.suppliers)` |
| `proveedor_id` | string | ID del primer proveedor adjudicado | `awards.suppliers[1].id` |
| `proveedor` | string | Nombre del primer proveedor adjudicado | `awards.suppliers[1].name` |
| `monto_adjudicado` | double | Σ cantidad × valor unitario de los ítems adjudicados | `awards.items` |
| `moneda` | string | Moneda del primer ítem adjudicado | `awards.items[1].unit.value.currency` |

### 2.3 `silver.contratos` — una fila por contrato firmado

| Columna | Tipo | Descripción | Origen OCDS |
| --- | --- | --- | --- |
| `ocid` | string | Proceso al que pertenece el contrato | `ocid` |
| `contrato_id` | string | Identificador del contrato | `contracts.id` |
| `award_id` | string | Adjudicación que origina el contrato | `contracts.awardID` |
| `estado_contrato` | string | Estado del contrato (`active`, …) | `contracts.status` |
| `titulo_contrato` | string | Título del contrato | `contracts.title` |
| `monto_contrato` | bigint | Monto contratado | `contracts.value.amount` |
| `moneda` | string | Moneda del contrato | `contracts.value.currency` |
| `inicio_contrato` | timestamp | Fecha de inicio del contrato | `contracts.period.startDate` |
| `fin_contrato` | timestamp | Fecha de fin del contrato | `contracts.period.endDate` |
| `flag_monto_invalido` | boolean | `true` si `monto_contrato` es nulo o ≤ 0 | derivado |
| `flag_fecha_incoherente` | boolean | `true` si `inicio_contrato` > `fin_contrato` | derivado |

### 2.4 `silver.proveedores` — catálogo de proveedores (parties con rol `supplier`)

| Columna | Tipo | Descripción | Origen OCDS |
| --- | --- | --- | --- |
| `party_id` | string | Identificador de la parte (clave) | `parties.id` |
| `rnc` | string | RNC del proveedor | `parties.identifier.id` |
| `nombre` | string | Nombre del proveedor (recortado) | `parties.name` |
| `escala` | string | Tamaño de empresa: `micro`, `small`, `medium`, `large` o `unspecified` | `parties.details.scale` |
| `genero` | string | Género del propietario/a de la empresa | `parties.details.gender` |
| `region` | string | Región / provincia | `parties.address.region` |

---

## 3. Gold — `compras_rd.gold.*`

Modelo estrella para análisis. Dimensiones con claves (`*_key`, `*_id`) y dos tablas de hechos, además de tres agregados precalculados para el dashboard.

### 3.1 `gold.dim_fecha` (dimensión de tiempo, calendario 2023-01-01 a 2027-12-31)

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `fecha_key` | int | Clave surrogada de fecha, formato `yyyyMMdd` (p. ej. 20240315) |
| `fecha` | date | Fecha |
| `anio` | int | Año |
| `trimestre` | int | Trimestre (1-4) |
| `mes` | int | Mes (1-12) |
| `nombre_mes` | string | Nombre del mes en español (enero…diciembre) |
| `dia_semana` | int | Día de la semana |

### 3.2 `gold.dim_institucion`

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `institucion_id` | string | Clave: ID de la institución compradora |
| `institucion` | string | Nombre de la institución (nombre más frecuente por ID) |

### 3.3 `gold.dim_modalidad`

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `modalidad` | string | Modalidad genérica (`open`, `direct`, `selective`) |
| `modalidad_detalle` | string | Modalidad específica (texto legal RD) |
| `modalidad_key` | int | Clave surrogada asignada por fila (1-10) |

### 3.4 `gold.dim_proveedor`

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `proveedor_id` | string | Clave: ID de la parte proveedora (= `party_id` en Silver) |
| `rnc` | string | RNC del proveedor |
| `nombre` | string | Nombre del proveedor |
| `escala` | string | Tamaño de empresa (`micro`, `small`, `medium`, `large`, `unspecified`) |
| `genero` | string | Género del propietario/a |
| `region` | string | Región / provincia |

### 3.5 `gold.fact_contratos` (tabla de hechos, 1 fila = 1 contrato)

Une `silver.contratos` + `silver.adjudicaciones` (por `ocid`+`award_id`) + datos del proceso (institución, modalidad). `fecha_key` se deriva de `coalesce(fecha_adjudicacion, inicio_contrato, fecha_publicacion)`.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `ocid` | string | Proceso de origen |
| `contrato_id` | string | Identificador del contrato |
| `award_id` | string | Adjudicación de origen |
| `fecha_key` | int | Clave a `dim_fecha` (fecha de referencia del contrato) |
| `institucion_id` | string | Clave a `dim_institucion` |
| `modalidad_key` | int | Clave a `dim_modalidad` |
| `proveedor_id` | string | Clave a `dim_proveedor` (primer proveedor adjudicado) |
| `num_proveedores` | int | Proveedores adjudicados en la adjudicación |
| `estado_contrato` | string | Estado del contrato |
| `monto_contrato` | bigint | Monto contratado |
| `monto_adjudicado` | double | Monto adjudicado (Σ ítems de la adjudicación) |
| `moneda` | string | Moneda del contrato |
| `inicio_contrato` | timestamp | Inicio del contrato |
| `fin_contrato` | timestamp | Fin del contrato |
| `duracion_dias` | int | Días entre inicio y fin del contrato |
| `flag_monto_invalido` | boolean | Contrato con monto nulo o ≤ 0 |
| `flag_fecha_incoherente` | boolean | Contrato con inicio posterior al fin |

### 3.6 `gold.fact_procesos` (tabla de hechos, 1 fila = 1 proceso)

Une `silver.procesos` con agregados por `ocid` de contratos y adjudicaciones.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `ocid` | string | Identificador del proceso (clave) |
| `fecha_key` | int | Clave a `dim_fecha` (derivada de `coalesce(inicio_oferta, fecha_publicacion)`) |
| `institucion_id` | string | Clave a `dim_institucion` |
| `modalidad_key` | int | Clave a `dim_modalidad` |
| `categoria` | string | Categoría principal de compra |
| `estado` | string | Estado de la licitación |
| `moneda` | string | Moneda del monto estimado |
| `monto_estimado` | double | Valor estimado de la licitación |
| `presupuesto` | double | Presupuesto planeado |
| `num_oferentes` | bigint | Número de oferentes |
| `num_adjudicaciones` | bigint | Adjudicaciones del proceso (agregado) |
| `num_contratos` | bigint | Contratos del proceso (agregado) |
| `monto_adjudicado` | double | Σ montos adjudicados del proceso |
| `monto_contratado` | bigint | Σ montos contratados (excluye montos inválidos) |
| `inicio_oferta` | timestamp | Inicio del período de ofertas |
| `fin_oferta` | timestamp | Fin del período de ofertas |
| `fin_adjudicacion` | timestamp | Fin del período de adjudicación |
| `dias_oferta` | int | Días que duró abierto el período de ofertas |
| `dias_hasta_adjudicacion` | int | Días desde el inicio de ofertas hasta el fin de la adjudicación (tiempo de adjudicación) |
| `flag_monto_invalido` | boolean | Proceso con monto estimado nulo o ≤ 0 |

### 3.7 `gold.agg_gasto_mensual` — gasto contratado por mes y moneda

Agregado de `fact_contratos` (solo montos válidos) unido a `dim_fecha`.

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `anio` | int | Año |
| `mes` | int | Mes (1-12) |
| `moneda` | string | Moneda |
| `num_contratos` | bigint | Contratos del mes |
| `monto_total` | bigint | Σ monto contratado |
| `monto_promedio` | double | Monto promedio por contrato |

### 3.8 `gold.agg_gasto_institucion` — gasto por institución y moneda

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `institucion_id` | string | ID de la institución |
| `institucion` | string | Nombre de la institución |
| `moneda` | string | Moneda |
| `num_contratos` | bigint | Contratos de la institución |
| `monto_total` | bigint | Σ monto contratado |

### 3.9 `gold.agg_proveedores` — concentración de proveedores (análisis Pareto, por moneda)

| Columna | Tipo | Descripción |
| --- | --- | --- |
| `proveedor_id` | string | ID del proveedor |
| `nombre` | string | Nombre del proveedor |
| `escala` | string | Tamaño de empresa |
| `genero` | string | Género del propietario/a |
| `moneda` | string | Moneda |
| `num_contratos` | bigint | Contratos del proveedor |
| `monto_total` | bigint | Σ monto contratado por el proveedor |
| `participacion` | double | % del gasto total de la moneda (0-1) |
| `participacion_acum` | double | % acumulado ordenando por monto descendente (curva Pareto) |
| `ranking` | int | Posición del proveedor por monto dentro de la moneda |

---

## 4. Modelo relacional (uniones)

* `fact_contratos.fecha_key` → `dim_fecha.fecha_key`
* `fact_contratos.institucion_id` → `dim_institucion.institucion_id`
* `fact_contratos.modalidad_key` → `dim_modalidad.modalidad_key` (en Silver se une por `modalidad` + `modalidad_detalle` con `eqNullSafe`)
* `fact_contratos.proveedor_id` → `dim_proveedor.proveedor_id`
* `fact_procesos` usa las mismas claves que `fact_contratos` (excepto proveedor)
* `fact_contratos.ocid` + `award_id` ← enlace con `silver.adjudicaciones`; `ocid` ← enlace con `silver.procesos`
* Verificación de cobertura: 100% de los contratos tiene proveedor, institución y fecha en sus dimensiones (sin claves huérfanas).

## 5. Reglas de calidad y consideraciones

* **Deduplicación:** 58.287 filas en Bronze con `ocid` únicos; la regla de deduplicación por `ocid` (fecha más reciente) no eliminó filas.
* **Montos inválidos:** `flag_monto_invalido = true` marca montos nulos o ≤ 0; se excluyen de las sumas (`monto_contratado` y los agregados Gold).
* **Fechas incoherentes:** `flag_fecha_incoherente = true` marca contratos cuyo inicio es posterior al fin. Hay contratos con `fin_contrato` hasta 2054 (plurianuales).
* **Monedas:** DOP 74.596 contratos (147.665.326.218 DOP), USD 79 contratos (72.770.712 USD), EUR 7 contratos (120.158.208 EUR). Los agregados están particionados por moneda; no mezclar sin convertir.
* **Escala de proveedores:** `unspecified` (7.381) es el valor más común, seguido de `micro` (2.438), `small` (1.635), `medium` (368) y `large` (130).
* **Cobertura temporal:** procesos publicados en 2024; adjudicaciones y contratos se extienden hasta 2026 (contratos firmados después de la publicación del proceso).
* **Escritura:** todas las tablas se escriben en Delta con `mode("overwrite")` + `overwriteSchema` (recarga completa, no incremental).

*Documento generado a partir de los esquemas reales de Unity Catalog y del código de los notebooks del proyecto (noviembre 2026).*