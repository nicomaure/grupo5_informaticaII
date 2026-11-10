# Guía para la defensa oral

Cada integrante debería poder responder estas preguntas y hacer al menos un cambio en vivo.

## Preguntas probables y respuesta corta

| Pregunta | Respuesta |
|---|---|
| ¿Dónde está la N:M? | `partida_pregunta`: una partida tiene muchas preguntas y una pregunta sale en muchas partidas. Atributos propios: `orden`, `id_opcion_elegida`, `fecha_respuesta`. |
| ¿Cuál es la estructura avanzada? | Reflexiva en `categoria` (`id_categoria_padre`). Se recorre con `WITH RECURSIVE` en `v_categoria_arbol`, en la consulta 6 y al sortear preguntas. |
| ¿Por qué `puntos` no está en `pregunta`? | Depende de la dificultad, no de la pregunta: sería una dependencia transitiva (rompe 3FN). |
| ¿Por qué no guardan el puntaje? | Es un dato derivado. Se calcula en `v_resultado_partida`, así nunca queda desactualizado (R7). |
| ¿Cómo evitan elegir una opción de otra pregunta? | FK compuesta `(id_opcion_elegida, id_pregunta) → opcion(id, id_pregunta)` (R3). |
| ¿Por qué un trigger y no un CHECK? | El CHECK solo mira la fila actual. Si la regla necesita contar filas o leer otra tabla (R2, R4, R5, R6), hace falta trigger. |
| ¿Qué pasa si se corta a la mitad al crear una partida? | Está dentro de una transacción en `sp_iniciar_partida`: o se crea completa o `ROLLBACK` (R8). |
| ¿RESTRICT o CASCADE? | CASCADE donde la fila hija no tiene sentido sola (opciones de una pregunta, preguntas de una partida). RESTRICT donde borrar dejaría historia sin sentido (no se borra un jugador con partidas ni una categoría con preguntas). |
| ¿Y el ON UPDATE? | `ON UPDATE RESTRICT` en todas las FK. Los `id` son artificiales y nunca se cambian; si alguien intenta cambiar uno que está referenciado, la base lo rechaza en vez de propagar el cambio. |
| ¿Qué hace la app PHP si la base rechaza algo? | Muestra el mensaje del error (`SIGNAL` R2…R6, FK, UNIQUE, CHECK). La validación está en la base, no en PHP. |

## Explicar cada consulta (sección 8 del script)

1. JOIN de 4 tablas + self-join: pregunta con su categoría, la categoría madre y la dificultad.
2. GROUP BY + HAVING: jugadores con 2 o más partidas y su % de aciertos.
3. Anti-join (`LEFT JOIN … IS NULL`): preguntas activas nunca jugadas.
4. Subconsulta escalar en WHERE: partidas por encima del promedio.
5. GROUP BY + HAVING: tasa de acierto por pregunta respondida 3+ veces.
6. Recursiva: preguntas por categoría raíz, contando subcategorías.
7. Dos roles de `opcion`: elegida vs correcta en la partida 1.
8. Subconsulta escalar en SELECT: distancia de cada jugador al récord.
9. Subconsultas correlacionadas: por qué los borradores no se pueden activar (R4).
10. GROUP BY + HAVING: opciones incorrectas más elegidas.

## Práctica de cambios en vivo

Probar cada uno en phpMyAdmin y después deshacerlo.

```sql
-- a) Agregar un CHECK: el alias no puede tener espacios
ALTER TABLE jugador ADD CONSTRAINT chk_jugador_sin_espacios CHECK (alias NOT LIKE '% %');
INSERT INTO jugador (alias) VALUES ('con espacio');   -- debe fallar
ALTER TABLE jugador DROP CONSTRAINT chk_jugador_sin_espacios;

-- b) Nueva consulta: cantidad de partidas por modo
SELECT m.nombre, COUNT(p.id) AS partidas
FROM modo_juego m
LEFT JOIN partida p ON p.id_modo_juego = m.id
GROUP BY m.id, m.nombre;

-- c) Agregar una subcategoría (usa la reflexiva)
INSERT INTO categoria (nombre, descripcion, id_categoria_padre)
VALUES ('Python', 'Lenguaje Python', 5);   -- 5 = Programación

-- d) Probar una regla: activar una pregunta sin opción correcta
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = 56;   -- debe fallar (R4)

-- e) Cambiar los puntos de una dificultad y ver el ranking recalculado
UPDATE dificultad SET puntos = 25 WHERE nombre = 'Media';
SELECT * FROM v_ranking LIMIT 5;
UPDATE dificultad SET puntos = 20 WHERE nombre = 'Media';
```

Para ver todas las reglas fallando a propósito, ejecutar `sql/pruebas_reglas.sql` sentencia por sentencia.
