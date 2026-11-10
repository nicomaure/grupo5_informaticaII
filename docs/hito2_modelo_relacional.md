# Hito 2 — Modelo relacional, normalización y diccionario de datos

> Borrador de trabajo del grupo Sala 5. Convención de la materia: cada tabla tiene `id INT AUTO_INCREMENT` como clave primaria artificial y las claves foráneas se llaman `id_<tabla>`. Las claves "del negocio" (alias, nombre, enunciado) quedan como `UNIQUE`.

## 1. Esquema relacional

PK = clave primaria · FK = clave foránea · UK = única

```text
jugador          (id PK, alias UK, fecha_alta)
categoria        (id PK, nombre UK, descripcion, id_categoria_padre FK→categoria.id NULL)
dificultad       (id PK, nombre UK, nivel UK, puntos)
modo_juego       (id PK, nombre UK, descripcion, cantidad_preguntas)
pregunta         (id PK, enunciado UK, explicacion, estado,
                  id_categoria FK→categoria.id, id_dificultad FK→dificultad.id)
opcion           (id PK, id_pregunta FK→pregunta.id, texto, es_correcta,
                  UK(id_pregunta, texto), UK(id, id_pregunta))
partida          (id PK, id_jugador FK→jugador.id, id_modo_juego FK→modo_juego.id,
                  id_categoria FK→categoria.id, estado, fecha_inicio, fecha_fin NULL)
partida_pregunta (id PK, id_partida FK→partida.id, id_pregunta FK→pregunta.id, orden,
                  id_opcion_elegida NULL, fecha_respuesta NULL,
                  FK(id_opcion_elegida, id_pregunta)→opcion(id, id_pregunta),
                  UK(id_partida, id_pregunta), UK(id_partida, orden))
```

**8 tablas.** Vistas: `v_categoria_arbol`, `v_pregunta_partida`, `v_resultado_partida`, `v_ranking`.

## 2. Cómo se transformó el MER

| Elemento del MER | Transformación |
|---|---|
| Relaciones 1:N (pertenece a, tiene nivel, tiene, juega, se juega en, es de) | La FK va del lado N: `pregunta.id_categoria`, `pregunta.id_dificultad`, `opcion.id_pregunta`, `partida.id_jugador`, `partida.id_modo_juego`, `partida.id_categoria`. |
| **Reflexiva** *subcategoría de* (CATEGORIA–CATEGORIA, N:1) | FK de la tabla hacia sí misma: `categoria.id_categoria_padre → categoria.id`. Admite NULL porque las categorías raíz no tienen padre. Los roles (hija/padre) quedan en el nombre de la columna. |
| **N:M con atributos** *incluye* (PARTIDA–PREGUNTA) | Tabla intermedia `partida_pregunta` con las FK `id_partida` e `id_pregunta`, más los atributos de la relación: `orden`, `id_opcion_elegida`, `fecha_respuesta`. Siguiendo la convención de la materia tiene `id` propio; la combinación `(id_partida, id_pregunta)` se mantiene como `UNIQUE`, que es la clave candidata real de la relación. |
| *elige* (respuesta → OPCION, N:1 opcional) | `partida_pregunta.id_opcion_elegida`, NULL hasta que se responde. Se usa una **FK compuesta** `(id_opcion_elegida, id_pregunta) → opcion(id, id_pregunta)` para que la opción sea de esa misma pregunta. Para eso `opcion` declara `UNIQUE (id, id_pregunta)`. |

**Decisión: la respuesta no es una tabla aparte.** Se evaluó una tabla `respuesta (id, id_partida_pregunta, id_opcion)`. Para validar que la opción sea de la pregunta habría que copiar `id_pregunta` en `respuesta`, y ese dato depende de `id_partida_pregunta` (dependencia transitiva: rompe 3FN). Como cada pregunta de la partida tiene como máximo una respuesta (1:1), los atributos de la respuesta se ubicaron en la propia relación `partida_pregunta`.

## 3. Normalización hasta 3FN

### Dependencias funcionales principales

```text
jugador:          id → alias, fecha_alta              alias → id
categoria:        id → nombre, descripcion, id_categoria_padre    nombre → id
dificultad:       id → nombre, nivel, puntos          nombre → id    nivel → id
modo_juego:       id → nombre, descripcion, cantidad_preguntas    nombre → id
pregunta:         id → enunciado, explicacion, estado, id_categoria, id_dificultad
                  enunciado → id
opcion:           id → id_pregunta, texto, es_correcta
                  (id_pregunta, texto) → id
partida:          id → id_jugador, id_modo_juego, id_categoria, estado, fecha_inicio, fecha_fin
partida_pregunta: id → id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta
                  (id_partida, id_pregunta) → id         (id_partida, orden) → id
```

En todas las tablas, cada determinante es una clave candidata (PK o UNIQUE).

### 1FN

Todos los atributos son atómicos y no hay grupos repetidos:

- Las opciones de una pregunta no son columnas `opcion1, opcion2, …`: son filas de `opcion`.
- Las preguntas de una partida no son una lista: son filas de `partida_pregunta`.

### 2FN

Las PK son simples (`id`), así que no hay dependencias parciales respecto de la PK. Las claves candidatas compuestas también cumplen. En `partida_pregunta`, ningún atributo depende solo de `id_partida` ni solo de `id_pregunta`: `orden` y la respuesta dependen de la combinación partida + pregunta. Por eso el enunciado de la pregunta **no** se copia en `partida_pregunta`, ni el alias del jugador en ella.

### 3FN: dependencias transitivas eliminadas

| Posible redundancia | Problema | Decisión |
|---|---|---|
| `puntos` dentro de `pregunta` | `pregunta.id → dificultad → puntos`: transitiva. Cambiar los puntos de "Media" obligaría a actualizar muchas filas. | Tabla `dificultad`; la pregunta guarda solo `id_dificultad`. |
| `cantidad_preguntas` dentro de `partida` | `partida.id → modo → cantidad`: transitiva. | Tabla `modo_juego`; la partida guarda `id_modo_juego`. |
| `puntaje` o `correctas` dentro de `partida` | Dato derivado de las respuestas: podría quedar desactualizado o editarse a mano. | No se guarda: se calcula en la vista `v_resultado_partida` (regla R7). |
| `es_correcta` dentro de `partida_pregunta` | Depende de la opción elegida, no de la partida: transitiva. | Se obtiene con un JOIN a `opcion`. |
| Nombre de la categoría padre en `categoria` | Depende de `id_categoria_padre`: transitiva. | Solo se guarda la FK; el nombre se obtiene con un self-join o con la vista `v_categoria_arbol`. |
| `id_pregunta` en una tabla `respuesta` | Transitiva (ver sección 2). | La respuesta se guarda en `partida_pregunta`. |

**Sobre `UNIQUE (id, id_pregunta)` en `opcion`:** no introduce redundancia. `id` ya es único; esta restricción no agrega datos, solo da un destino a la FK compuesta que impone la regla R3.

**Política ON UPDATE:** todas las claves foráneas usan `ON UPDATE RESTRICT`. Los `id` son artificiales (AUTO_INCREMENT) y no tienen significado en el juego, así que nunca se modifican; si alguien intenta cambiar un `id` que otra tabla está usando, la base lo rechaza. La política `ON DELETE` de cada FK se indica en el diccionario.

## 4. Diccionario de datos

### jugador — quien juega

| Columna | Tipo | Restricciones | Significado en el juego |
|---|---|---|---|
| id | INT | PK, AUTO_INCREMENT | Identificador interno |
| alias | VARCHAR(30) | NOT NULL, UNIQUE, CHECK largo ≥ 3 | Nombre que se ve en el ranking |
| fecha_alta | DATETIME | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Cuándo jugó por primera vez |

### categoria — temas de preguntas (reflexiva)

| Columna | Tipo | Restricciones | Significado |
|---|---|---|---|
| id | INT | PK, AUTO_INCREMENT | |
| nombre | VARCHAR(60) | NOT NULL, UNIQUE | Ej.: "SQL" |
| descripcion | VARCHAR(200) | NULL | Texto de ayuda |
| id_categoria_padre | INT | NULL, FK → categoria.id ON DELETE RESTRICT | Categoría madre; NULL = raíz |

### dificultad — nivel y puntos

| Columna | Tipo | Restricciones | Significado |
|---|---|---|---|
| id | INT | PK, AUTO_INCREMENT | |
| nombre | VARCHAR(20) | NOT NULL, UNIQUE | Fácil / Media / Difícil |
| nivel | INT | NOT NULL, UNIQUE, CHECK 1–5 | Orden de dificultad |
| puntos | INT | NOT NULL, CHECK > 0 | Puntos que da un acierto |

### modo_juego — tipo de partida

| Columna | Tipo | Restricciones | Significado |
|---|---|---|---|
| id | INT | PK, AUTO_INCREMENT | |
| nombre | VARCHAR(30) | NOT NULL, UNIQUE | Relámpago / Clásico / Maratón |
| descripcion | VARCHAR(200) | NOT NULL | Texto en la pantalla de inicio |
| cantidad_preguntas | INT | NOT NULL, CHECK 3–20 | Preguntas que tiene la partida |

### pregunta — contenido del juego

| Columna | Tipo | Restricciones | Significado |
|---|---|---|---|
| id | INT | PK, AUTO_INCREMENT | |
| enunciado | VARCHAR(255) | NOT NULL, UNIQUE | Texto de la pregunta |
| explicacion | VARCHAR(255) | NULL | Se muestra después de responder |
| estado | VARCHAR(10) | NOT NULL, DEFAULT 'BORRADOR', CHECK IN ('BORRADOR','ACTIVA') | Solo las ACTIVAS salen en partidas |
| id_categoria | INT | NOT NULL, FK → categoria.id RESTRICT | Tema |
| id_dificultad | INT | NOT NULL, FK → dificultad.id RESTRICT | Nivel y puntos |

### opcion — alternativas de respuesta

| Columna | Tipo | Restricciones | Significado |
|---|---|---|---|
| id | INT | PK, AUTO_INCREMENT | |
| id_pregunta | INT | NOT NULL, FK → pregunta.id CASCADE | Pregunta a la que pertenece |
| texto | VARCHAR(150) | NOT NULL, UNIQUE con id_pregunta | Texto del botón |
| es_correcta | TINYINT(1) | NOT NULL, DEFAULT 0, CHECK IN (0,1) | 1 = respuesta correcta |
| — | — | UNIQUE (id, id_pregunta) | Destino de la FK compuesta (R3) |

### partida — cada intento

| Columna | Tipo | Restricciones | Significado |
|---|---|---|---|
| id | INT | PK, AUTO_INCREMENT | |
| id_jugador | INT | NOT NULL, FK → jugador.id RESTRICT | Quién juega |
| id_modo_juego | INT | NOT NULL, FK → modo_juego.id RESTRICT | Cuántas preguntas |
| id_categoria | INT | NOT NULL, FK → categoria.id RESTRICT | Rama elegida |
| estado | VARCHAR(12) | NOT NULL, DEFAULT 'EN_CURSO', CHECK IN ('EN_CURSO','FINALIZADA') | |
| fecha_inicio | DATETIME | NOT NULL, DEFAULT CURRENT_TIMESTAMP | |
| fecha_fin | DATETIME | NULL; CHECK emparejado con estado y fecha_fin ≥ fecha_inicio | Se completa al finalizar |

### partida_pregunta — N:M partida–pregunta con la respuesta dada

| Columna | Tipo | Restricciones | Significado |
|---|---|---|---|
| id | INT | PK, AUTO_INCREMENT | |
| id_partida | INT | NOT NULL, FK → partida.id CASCADE | |
| id_pregunta | INT | NOT NULL, FK → pregunta.id RESTRICT; UNIQUE con id_partida (R1) | |
| orden | INT | NOT NULL, CHECK > 0; UNIQUE con id_partida | Posición 1..N en la partida |
| id_opcion_elegida | INT | NULL; FK compuesta (id_opcion_elegida, id_pregunta) → opcion(id, id_pregunta) (R3) | NULL = sin responder |
| fecha_respuesta | DATETIME | NULL; CHECK: NULL ⇔ id_opcion_elegida NULL | Cuándo respondió |

### Objetos de la base que imponen reglas

| Objeto | Tipo | Regla |
|---|---|---|
| trg_pregunta_bi / trg_pregunta_bu | trigger | R4 |
| trg_opcion_bi / trg_opcion_bu / trg_opcion_bd | trigger | R4 |
| trg_pp_bi | trigger | R5 |
| trg_pp_bu | trigger | R2 |
| trg_partida_bu | trigger | R6 |
| sp_iniciar_partida | procedimiento + transacción | R8 (y usa la reflexiva con WITH RECURSIVE) |
| sp_responder | procedimiento + transacción | Responder y finalizar de forma atómica |
| v_resultado_partida | vista | R7 |

## 5. Correcciones respecto del Hito 1

_Completar después de la corrección del docente: qué cambió y por qué._
