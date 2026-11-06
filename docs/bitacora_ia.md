# Bitácora de uso de IA

> Las consignas permiten usar IA, pero cada integrante tiene que poder explicar y modificar lo entregado en la defensa oral. Registrar acá cada uso relevante.

| Fecha | Integrante | Herramienta | Qué se pidió | Qué se obtuvo | Qué revisamos / corregimos |
|---|---|---|---|---|---|
| 2026-11-03 | Nicolás Maure | Perplexity Computer | Generar el proyecto completo: script SQL siguiendo las convenciones de la materia, aplicación PHP + HTML, README y borradores de documentación. | Script `sql/desafio_sala5.sql` (8 tablas, triggers, vistas, procedimientos, semilla, transacción y 10 consultas), `sql/pruebas_reglas.sql`, carpeta `app/`, documentos en `docs/`. | _Pendiente:_ redibujar el MER en Miro, revisar cada regla y consulta, ejecutar `pruebas_reglas.sql`, adaptar textos con palabras propias. |
| 2026-11-06 | Nicolás Maure | Perplexity Computer | Revisar el PR #1 de Elías Aguero (10 preguntas nuevas) y verificar compatibilidad con el SQL y el PHP. | Se detectó que el script fallaba al importar (error 1644, regla R4: las preguntas se insertaban directamente en ACTIVA). Se corrigió con el patrón BORRADOR → opciones → ACTIVA y se renombró la categoría a "Cultura general". | Probado en MariaDB 11.8: importa completo, la categoría tiene 10 preguntas activas, Relámpago y Clásico funcionan, Maratón avisa que no alcanzan. PHP sin cambios. Versión anterior en `sql/old/desafio_sala5_v1.sql`. |
| | | | | | |

## Criterios del grupo

1. Nada se entrega sin que al menos un integrante lo haya ejecutado y entendido.
2. El MER se dibuja a mano o en Miro por el grupo (no se copia el diagrama generado).
3. Si la IA propone algo que no entendemos, se pregunta o se simplifica.
4. Se anotan los errores de la IA que encontramos y cómo los corregimos.
