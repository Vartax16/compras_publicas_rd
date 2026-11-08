# Arquitectura — Compras Públicas RD 2024

**Proyecto:** Análisis de las contrataciones públicas de República Dominicana (año 2024) sobre Databricks.
**Fuente:** API de compras públicas de RD exportada en formato OCDS (Open Contracting Data Standard).

Este documento describe la **arquitectura de la solución**: componentes, flujo de datos, decisiones de diseño y organización del workspace. El detalle del modelo de datos está en [modelo_datos.md](modelo_datos.md) y el de columnas en [diccionario_datos.md](diccionario_datos.md).

---

## 1. Visión general

Solución analítica de tipo lakehouse sobre Unity Catalog con arquitectura medallón, ejecutada como pipeline de notebooks en batch:

```
┌────────────────────────────────────────────────────────────────────────┐
│ FUENTE                                                                 │
│ API de compras públicas RD (OCDS)                                      │
│ → export manual: dominican_republic_api_2024.jsonl.gz (≈45,6 MB)      │
│   en /Volumes/compras_rd/bronze/raw_files/                             │
└──────────────────────────────┬─────────────────────────────────────────┘
                               │  01_bronze_ingesta  (spark.read.json)
┌──────────────────────────────▼─────────────────────────────────────────┐
│ UNITY CATALOG — catálogo compras_rd                                     │
│                                                                         │
│  schema bronze ── 02_silver_limpieza ──► schema silver ──┐              │
│  contratos_raw (Delta)                                    │              │
│                            03_gold_modelo                 │              │
│                                                           ▼              │
│  ┌─────────────────────────────────────────────────────┐               │
│  │ schema gold — modelo estrella + agregados (Delta)    │               │
│  └─────────────────────────────────────────────────────┘               │
└──────────────────────────────┬─────────────────────────────────────────┘
                               │  04_analisis + sql/q00–q09b
┌──────────────────────────────▼─────────────────────────────────────────┐
│ CAPA ANALÍTICA / BI                                                     │
│ Dashboard "Compras públicas RD 2024" (AI/BI) · consultas SQL guardadas  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Componentes

### 2.1 Almacenamiento de la fuente — UC Volume

* El archivo fuente comprimido (.jsonl.gz) reside en el Volume `/Volumes/compras_rd/bronze/raw_files/` (Unity Catalog: catalog `compras_rd`, schema `bronze`, volume `raw_files`).
* La carga inicial del archivo al Volume es manual (export de la API); no existe conector de ingesta directa.

### 2.2 Unity Catalog — catálogo `compras_rd`

Un solo catálogo con tres esquemas que materializan el medallón:

| Esquema | Rol | Tablas |
| --- | --- | --- |
| `compras_rd.bronze` | Datos crudos OCDS tal cual + columnas de auditoría | `contratos_raw` |
| `compras_rd.silver` | Entidades limpias y aplanadas | `procesos`, `adjudicaciones`, `contratos`, `proveedores` |
| `compras_rd.gold` | Modelo estrella analítico + agregados | `dim_fecha`, `dim_institucion`, `dim_modalidad`, `dim_proveedor`, `fact_contratos`, `fact_procesos`, `agg_gasto_mensual`, `agg_gasto_institucion`, `agg_proveedores` |

Todas las tablas son Delta, gestionadas por Unity Catalog (governance, linaje y permisos centralizados).

### 2.3 Pipeline — notebooks como etapas

El pipeline es una **secuencia fija de cuatro notebooks** en `notebooks/`, ejecutados en orden (manualmente, de momento — no hay job ni orquestador):

| # | Notebook | Responsabilidad | Lee | Escribe |
| --- | --- | --- | --- | --- |
| 01 | `01_bronze_ingesta` | Ingesta del JSON OCDS a Delta, añade `_ingest_ts` y `_source_file` como auditoría, y valida (conteo, esquema, muestra) | Volume `raw_files` | `bronze.contratos_raw` |
| 02 | `02_silver_limpieza` | Aplanado del JSON anidado, parseo de fechas (`try_to_timestamp`), dedup por `ocid`, flags de calidad | `bronze.contratos_raw` | 4 tablas `silver.*` |
| 03 | `03_gold_modelo` | Dimensiones con claves, tablas de hechos, agregados y verificación de integridad (0 claves huérfanas) | `silver.*` | 9 tablas `gold.*` |
| 04 | `04_analisis` | Exploración y preguntas analíticas sobre Gold | `gold.*` | — |

Cada notebook crea sus esquemas destino si no existen (`CREATE SCHEMA IF NOT EXISTS`) y escribe con `mode("overwrite")` + `overwriteSchema` (recarga completa). El notebook 03 imprime conteos por tabla y ejecuta un chequeo de cobertura de joins.

### 2.4 Capa analítica — SQL y dashboard

* **Consultas guardadas** en `sql/` (`q00`–`q09b`), versionadas como archivos .sql del workspace: monedas, KPIs, gasto mensual e institucional, Pareto y top proveedores, modalidades, tiempos de adjudicación, MIPYMES y género, estimado vs. contratado, y alertas (un oferente, proveedor dominante).
* **Dashboard** "Compras públicas RD 2024" (AI/BI Lakeview) en `dashboards/`, que consume las consultas sobre Gold (hechos + agregados).

### 2.5 Documentación

`README.md` (proyecto, preguntas, hallazgos), `docs/diccionario_datos.md` (columnas), `docs/modelo_datos.md` (modelo) y este documento.

---

## 3. Flujo de datos y procesamiento

* **Patrón:** batch de una sola pasada sobre el archivo 2024 (no hay streaming ni ingesta incremental).
* **Idempotencia:** cada ejecución reescribe la tabla completa con `overwrite`; reejecutar produce el mismo resultado (fuente estática).
* **Trazabilidad:** `_ingest_ts` y `_source_file` en Bronze; cualquier fila Gold se rastrea a Silver por `ocid`/`contrato_id`/`award_id` y de ahí al JSON crudo.
* **Calidad:** las reglas (fechas, montos inválidos, dedup) se aplican en Silver y se propagan como flags a Gold; las sumas siempre excluyen montos inválidos y separan por moneda.

## 4. Organización del workspace

```
compras_publicas_rd/
├── README.md                  # visión del proyecto, preguntas, hallazgos
├── notebooks/                 # pipeline: 01_bronze_ingesta … 04_analisis
├── sql/                       # q00–q09b: consultas del análisis y el dashboard
├── dashboards/                # "Compras públicas RD 2024" (lvdash.json)
└── docs/                      # diccionario_datos · modelo_datos · arquitectura
```

Convención de nombres: notebooks numerados por etapa (`NN_propósito`), consultas por pregunta (`qNN_tema`), tablas por capa y rol (`dim_*`, `fact_*`, `agg_*`).

---

## 5. Decisiones de diseño

| Decisión | Justificación |
| --- | --- |
| Medallón en un solo catálogo | Proyecto analítico acotado a un año de datos; un catálogo `compras_rd` simplifica permisos y navegación. |
| Notebook por etapa (sin Lakeflow Jobs) | Pipeline exploratorio de una sola fuente estática; la orquestación formal se puede añadir después sin cambiar las etapas. |
| Recarga completa (`overwrite`) | Volumen pequeño (58K procesos) y fuente estática: más simple que un CDC. |
| `dim_fecha` fija 2023–2027 | Independiente de los datos, garantiza joins de fecha incluso con contratos plurianuales (hasta 2054). |
| Monedas sin convertir | No existe tasa de cambio oficial en la fuente; DOP/USD/EUR se separan por columna `moneda`. |
| Agregados precalculados | El dashboard lee tablas pequeñas (50–7.900 filas) en lugar de re-agregar hechos en cada widget. |
| Proveedor adjudicado = primero | OCDS permite varios proveedores por adjudicación; se conserva el primero + el total (`num_proveedores`). |

---

## 6. Reejecución y mantenimiento

1. (Opcional) Colocar un nuevo `.jsonl.gz` en `/Volumes/compras_rd/bronze/raw_files/` y ajustar `ruta` en `01_bronze_ingesta`.
2. Ejecutar los notebooks **en orden 01 → 02 → 03** (04 y el dashboard solo leen Gold).
3. Verificar en la salida de 03: conteos por tabla y el chequeo de cobertura de joins (debe reportar 0 nulos).

Posibles evoluciones: orquestar 01–03 como un Lakeflow Job con calendario, ingerir más años de la API, y añadir conversión de moneda con una tabla de tasas.

---

*Documento elaborado a partir de los notebooks, consultas y esquemas reales del proyecto (noviembre 2026). Complementa a [modelo_datos.md](modelo_datos.md) y [diccionario_datos.md](diccionario_datos.md).*