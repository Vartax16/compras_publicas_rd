# Modelo de Datos — Compras Públicas RD 2024

**Proyecto:** Análisis de las contrataciones públicas de República Dominicana (año 2024).
**Catálogo de Unity Catalog:** `compras_rd` | **Fuente:** OCDS (`/Volumes/compras_rd/bronze/raw_files/dominican_republic_api_2024.jsonl.gz`).

Este documento describe el **modelo de datos** del proyecto: capas, granularidades, modelo estrella Gold, claves y reglas de integración. El detalle columna por columna está en [diccionario_datos.md](diccionario_datos.md).

---

## 1. Visión general

El modelo sigue la arquitectura medallón dentro del catálogo `compras_rd`:

```
JSON OCDS (raw_files)
        │  01_bronze_ingesta
        ▼
┌─────────────────────────────────────────────────┐
│ BRONZE  compras_rd.bronze.contratos_raw          │  1 fila = 1 release OCDS (ocid)
│         JSON anidado sin transformar + auditoría │  58.287 filas
└───────────────────────┬─────────────────────────┘
                        │  02_silver_limpieza (aplanado, fechas, dedup, flags)
                        ▼
┌─────────────────────────────────────────────────┐
│ SILVER  procesos · adjudicaciones · contratos ·  │  1 tabla por entidad del proceso
│         proveedores                              │  de compra (modelado por ocid)
└───────────────────────┬─────────────────────────┘
                        │  03_gold_modelo (claves surrogadas, agregación)
                        ▼
┌─────────────────────────────────────────────────┐
│ GOLD    dim_fecha · dim_institucion ·           │  Modelo estrella + agregados
│         dim_modalidad · dim_proveedor            │  para el dashboard
│         fact_contratos · fact_procesos           │
│         agg_gasto_mensual · agg_gasto_institucion · agg_proveedores
└─────────────────────────────────────────────────┘
```

Cada capa se construye en un notebook (`01_bronze_ingesta` → `02_silver_limpieza` → `03_gold_modelo`) y se escribe en Delta con recarga completa (`overwrite` + `overwriteSchema`).

---

## 2. Capa Silver — modelo por entidad

Un proceso de compra OCDS tiene una estructura jerárquica natural (1 proceso → N adjudicaciones → N contratos; N proveedores participantes). Silver la aplanó en **cuatro tablas en tercera forma normal, una por entidad**, unidas por `ocid` y `award_id`:

| Tabla | Granularidad (1 fila =) | Clave primaria | Filas |
| --- | --- | --- | --- |
| `silver.procesos` | un proceso de licitación | `ocid` | 58.287 |
| `silver.adjudicaciones` | una adjudicación | `ocid`, `award_id` | 57.162 |
| `silver.contratos` | un contrato firmado | `contrato_id` | 74.682 |
| `silver.proveedores` | un proveedor (party con rol `supplier`) | `party_id` | 11.952 |

Relaciones en Silver:

* `contratos.ocid` + `contratos.award_id` → `adjudicaciones` (un contrato nace de una adjudicación).
* `contratos.ocid` y `adjudicaciones.ocid` → `procesos` (todo contrato/adjudicación pertenece a un proceso).
* `adjudicaciones.proveedor_id` → `proveedores.party_id` (primer proveedor adjudicado).

En esta capa se aplican las reglas de calidad transversales (sección 5): parseo de fechas con `try_to_timestamp`, deduplicación por `ocid`, `flag_monto_invalido` y `flag_fecha_incoherente`.

---

## 3. Capa Gold — modelo estrella

Gold es un **modelo estrella** con dos tablas de hechos compartiendo las mismas dimensiones:

```
                    ┌──────────────────┐
                    │    dim_fecha     │  1.826 filas (2023–2027)
                    │  fecha_key (int) │  calendario independiente
                    └───▲──────────▲───┘
                        │          │
┌──────────────────┐    │          │    ┌──────────────────────┐
│ dim_institucion  │◄───┤          ├───►│    dim_modalidad     │
│ institucion_id   │    │          │    │ modalidad_key (int)  │
│ (447 filas)      │    │          │    │ (10 filas)           │
└──────────────────┘    │          │    └──────────────────────┘
                        │          │
              ┌─────────┴──┐    ┌──┴─────────────┐   ┌──────────────────┐
              │fact_contratos│  │ fact_procesos  │◄─►│  dim_proveedor   │
              │ 74.682 filas │  │ 58.287 filas   │   │ proveedor_id     │
              │ 1 fila=contrato│ │ 1 fila=proceso │   │ (11.952 filas)   │
              └──────────────┘    └────────────────┘   └──────────────────┘
```

### 3.1 Dimensiones

| Dimensión | Clave | Tipo de clave | Descripción |
| --- | --- | --- | --- |
| `dim_fecha` | `fecha_key` (int, `yyyyMMdd`) | surrogada generada | Calendario fijo 2023-01-01 a 2027-12-31, independiente de los datos. Atributos: `anio`, `trimestre`, `mes`, `nombre_mes`, `dia_semana`. |
| `dim_institucion` | `institucion_id` (string) | natural (ID OCDS de la entidad compradora) | Una institución por ID (nombre más frecuente por ID). |
| `dim_modalidad` | `modalidad_key` (int) | surrogada (`row_number` sobre `modalidad` + `modalidad_detalle`) | 10 combinaciones modalidad genérica (`open`/`direct`/`selective`) × modalidad específica legal RD. |
| `dim_proveedor` | `proveedor_id` (string) | natural (= `party_id` en Silver) | Atributos descriptivos: `rnc`, `nombre`, `escala` (tamaño de empresa), `genero`, `region`. |

Nota: las dimensiones no llevan historia (SCD tipo 1); una recarga sobrescribe el estado actual.

### 3.2 Tablas de hechos

**`fact_contratos` — granularidad: 1 fila = 1 contrato** (74.682)

Une `silver.contratos` ← `adjudicaciones` (por `ocid` + `award_id`) ← `procesos` (por `ocid`). Es la tabla analítica central del gasto:

* **Claves foráneas:** `fecha_key`, `institucion_id`, `modalidad_key`, `proveedor_id` (las cuatro dimensiones).
* **Dimensiones degeneradas:** `ocid`, `contrato_id`, `award_id` (identificadores del negocio conservados en el hecho, sin dimensión propia).
* **Medidas:** `monto_contrato`, `monto_adjudicado`, `duracion_dias`, `num_proveedores` (aditivas; sumar solo montos con `flag_monto_invalido = false`).
* **Fecha de referencia:** `fecha_key` se deriva de `coalesce(fecha_adjudicacion, inicio_contrato, fecha_publicacion)`.

**`fact_procesos` — granularidad: 1 fila = 1 proceso** (58.287)

Une `silver.procesos` con agregados por `ocid` de adjudicaciones y contratos. Es la vista de eficiencia del proceso:

* **Claves foráneas:** `fecha_key` (derivada de `coalesce(inicio_oferta, fecha_publicacion)`), `institucion_id`, `modalidad_key`. Sin dimensión proveedor (un proceso puede tener muchos).
* **Medidas:** `monto_estimado`, `presupuesto`, `monto_adjudicado`, `monto_contratado`, `num_oferentes`, `num_adjudicaciones`, `num_contratos`, `dias_oferta`, `dias_hasta_adjudicacion`.

### 3.3 Agregados precalculados (para el dashboard)

| Tabla | Granularidad | Uso |
| --- | --- | --- |
| `agg_gasto_mensual` (50) | año × mes × moneda | Serie temporal de gasto; `monto_total`, `monto_promedio`. |
| `agg_gasto_institucion` (418) | institución × moneda | Ranking de gasto por institución. |
| `agg_proveedores` (7.900) | proveedor × moneda | Curva de Pareto: `participacion`, `participacion_acum`, `ranking`. |

Todos se calculan desde `fact_contratos` **excluyendo montos inválidos** y **particionados por moneda** (DOP/USD/EUR no se mezclan).

---

## 4. Integridad referencial

Reglas de unión del modelo estrella:

| Hecho → Dimensión | Clave | Cobertura verificada |
| --- | --- | --- |
| `fact_contratos.fecha_key` → `dim_fecha.fecha_key` | int | 100 % |
| `fact_contratos.institucion_id` → `dim_institucion.institucion_id` | string | 100 % |
| `fact_contratos.modalidad_key` → `dim_modalidad.modalidad_key` | int | 100 % |
| `fact_contratos.proveedor_id` → `dim_proveedor.proveedor_id` | string | 100 % |

* La unión proceso → modalidad en Silver se hace por `modalidad` + `modalidad_detalle` con `eqNullSafe` (tolera nulos antes de asignar la clave surrogada).
* Verificación de integridad en la celda final de `03_gold_modelo`: **0 claves huérfanas** (todo contrato tiene proveedor, institución y fecha en sus dimensiones).
* Trazabilidad al origen: cualquier fila Gold se puede rastrear a Silver vía `ocid` / `contrato_id` / `award_id`, y de ahí al JSON OCDS crudo en Bronze.

---

## 5. Reglas de calidad y supuestos del modelo

* **Deduplicación:** Bronze se deduplica por `ocid` conservando el release más reciente; en la práctica los 58.287 `ocid` ya son únicos.
* **Montos inválidos:** `flag_monto_invalido` (monto nulo o ≤ 0) — las filas se mantienen para conteo pero **se excluyen de toda suma** (`monto_contratado`, agregados).
* **Fechas incoherentes:** `flag_fecha_incoherente` (inicio > fin) — no se corrigen; se marcan para análisis.
* **Monedas:** el modelo **no convierte divisas**; DOP, USD y EUR conviven separadas por la columna `moneda`. Toda métrica financiera debe filtrar por moneda.
* **Cobertura temporal:** procesos de 2024; adjudicaciones y contratos se extienden hasta 2026 (por eso `dim_fecha` cubre 2023–2027 y hay contratos plurianuales con fin hasta 2054).
* **Proveedor adjudicado:** cuando una adjudicación tiene varios proveedores, se conserva el **primero** (`proveedor_id`) y el total (`num_proveedores`).

---

## 6. Volumetría

| Capa | Tabla | Filas |
| --- | --- | --- |
| Bronze | `contratos_raw` | 58.287 |
| Silver | `procesos` / `adjudicaciones` / `contratos` / `proveedores` | 58.287 / 57.162 / 74.682 / 11.952 |
| Gold | `dim_fecha` / `dim_institucion` / `dim_modalidad` / `dim_proveedor` | 1.826 / 447 / 10 / 11.952 |
| Gold | `fact_contratos` / `fact_procesos` | 74.682 / 58.287 |
| Gold | `agg_gasto_mensual` / `agg_gasto_institucion` / `agg_proveedores` | 50 / 418 / 7.900 |

---

*Documento elaborado a partir del código de los notebooks del proyecto y los esquemas reales de Unity Catalog (noviembre 2026). Véase también [diccionario_datos.md](diccionario_datos.md) para el detalle de columnas.*