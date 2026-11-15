# Desafío Sala 5 — Trivia con base de datos

Proyecto **"Una base de datos que se juega"** · Informática II · UNNE
Grupo Sala 5: Elías Agüero · Edgardo Molina · Nicolás Maure · Gabriel Martínez Canepa

Juego de preguntas y respuestas por **categorías jerárquicas** (Informática › Bases de datos › SQL), con **tres modos de juego** (Relámpago 5, Clásico 10, Maratón 15) y **ranking**. Las reglas del juego viven en MariaDB: la aplicación PHP solo llama a procedimientos, lee vistas y muestra los mensajes que devuelve la base.

| Tecnología | Uso |
|---|---|
| MariaDB 10.6+ | Modelo, reglas (triggers, CHECK, UNIQUE, FK), vistas y transacciones |
| PHP 8.1+ con PDO | Front web (HTML + CSS + un poco de JS), sin frameworks |
| phpMyAdmin | Importar el script SQL |

---

## Estructura del repositorio

```text
grupo5_informaticaII/
├── sql/
│   ├── desafio_sala5.sql     ← Hito 3: script único (DDL, reglas, vistas, datos, transacción, 10 consultas)
│   ├── pruebas_reglas.sql    ← sentencias que DEBEN fallar: prueban cada regla (defensa)
│   └── usuario_app.sql       ← opcional: usuario "juego5" con permisos mínimos
├── app/                      ← Hito 4: la aplicación jugable
│   ├── index.php             ← inicio: alias, modo, categoría, top 5
│   ├── iniciar.php           ← llama a sp_iniciar_partida
│   ├── jugar.php             ← pregunta actual y devolución (vista v_pregunta_partida)
│   ├── responder.php         ← llama a sp_responder
│   ├── resultado.php         ← resultado y repaso (vista v_resultado_partida)
│   ├── ranking.php           ← ranking (vista v_ranking)
│   ├── config.example.php    ← plantilla de conexión (copiar a config.local.php)
│   ├── includes/             ← conexión PDO y plantilla HTML
│   └── assets/               ← estilos y JS de interfaz
├── docs/
│   ├── hito1_idea_reglas_mer.md
│   ├── hito2_modelo_relacional.md
│   ├── hito4_informe_final.md
│   ├── bitacora_ia.md
│   └── guia_defensa.md
└── index.php                 ← redirige a app/
```

---

## Instalación en el servidor Azure del grupo

### 1. Cargar la base (phpMyAdmin)

1. Entrar a <https://nicomaure.canadacentral.cloudapp.azure.com/phpmyadmin> con el usuario `grupo5`.
2. Hacer clic en la base **grupo5** (panel izquierdo).
3. Pestaña **Importar** → elegir `sql/desafio_sala5.sql` → **Importar**.
4. Al terminar deben aparecer 8 tablas y 4 vistas. Se puede re-importar cuantas veces haga falta: el script borra y vuelve a crear todo.

> El script usa `grupo5` si ya existe; de lo contrario, intenta crearla.

### 2. Publicar la aplicación (git clone)

Por SSH en el servidor:

```bash
cd /var/www/html/informaticaII/php
git clone https://github.com/nicomaure/grupo5_informaticaII.git grupo5
cd grupo5/app
cp config.example.php config.local.php
nano config.local.php        # poner la clave real de la base en 'db_pass'
```

Abrir: <https://nicomaure.canadacentral.cloudapp.azure.com/informaticaII/php/grupo5/app/>

Si `git clone` da "Permission denied", la carpeta es de otro usuario:

```bash
sudo chown -R $USER:www-data /var/www/html/informaticaII/php
```

### 3. Actualizar cuando alguien sube cambios

```bash
cd /var/www/html/informaticaII/php/grupo5
git pull
```

`config.local.php` no está en el repositorio (`.gitignore`), así que `git pull` nunca pisa la clave. Si cambió el SQL, hay que volver a importarlo en phpMyAdmin.

### 4. (Opcional) Usuario de la app con permisos mínimos

Para que la página web no use la cuenta que puede borrar tablas:

```bash
nano sql/usuario_app.sql     # cambiar CAMBIAR_ESTA_CLAVE
sudo mariadb < sql/usuario_app.sql
```

Después, en `config.local.php`, poner `'db_user' => 'juego5'` y su clave. Ese usuario solo puede leer, registrar jugadores y ejecutar los procedimientos.

---

## Instalación en una máquina limpia (para el profesor)

Requisitos: MariaDB 10.6+ (o MySQL 8) y PHP 8.1+ con la extensión `pdo_mysql`.

```bash
# 1. Usuario y permisos (el script SQL crea la db)
sudo mariadb -e "CREATE USER 'grupo5'@'localhost' IDENTIFIED BY 'clave';
                 GRANT ALL PRIVILEGES ON grupo5.* TO 'grupo5'@'localhost';"
mariadb -ugrupo5 -pclave < sql/desafio_sala5.sql

# 2. Configuración
cp app/config.example.php app/config.local.php   # poner 'clave' en db_pass

# 3. Ejecutar
php -S localhost:8000
# abrir http://localhost:8000/app/
```

Con XAMPP: copiar la carpeta a `htdocs`, importar el SQL en phpMyAdmin y abrir `http://localhost/grupo5_informaticaII/app/`.

---

## Cómo se juega

1. Escribir un alias (mínimo 3 caracteres), elegir modo y categoría.
2. La base sortea las preguntas activas de esa categoría **y de todas sus subcategorías**.
3. Cada respuesta muestra si fue correcta, la opción correcta y una explicación.
4. Al responder la última, la base finaliza la partida: resultado, medalla y puesto en el ranking.

Puntaje: Fácil 10 · Media 20 · Difícil 30 puntos por acierto. A igual puntaje, gana quien tardó menos.

---

## Dónde vive cada regla

| # | Regla | Dónde se impone en la base |
|---|---|---|
| R1 | Una pregunta no se repite en una partida | `UNIQUE uq_pp_partida_pregunta (id_partida, id_pregunta)` |
| R2 | Una pregunta se responde una sola vez, y solo con la partida EN_CURSO | trigger `trg_pp_bu` |
| R3 | La opción elegida pertenece a esa pregunta | FK compuesta `fk_pp_opcion_de_pregunta` → `opcion (id, id_pregunta)` |
| R4 | Una pregunta ACTIVA tiene exactamente una opción correcta (y sus opciones quedan congeladas) | triggers `trg_pregunta_bi`, `trg_pregunta_bu`, `trg_opcion_bi/bu/bd` |
| R5 | La partida tiene exactamente las preguntas de su modo, solo ACTIVAS | trigger `trg_pp_bi` |
| R6 | Una partida se finaliza solo completa; finalizada no se modifica | trigger `trg_partida_bu` + `CHECK chk_partida_fin` |
| R7 | El puntaje sale solo de las respuestas registradas | vista `v_resultado_partida` (no existe columna puntaje) |
| R8 | Una partida se crea completa o no se crea | transacción en `sp_iniciar_partida` |

Para probarlas: `sql/pruebas_reglas.sql` (ejecutar las sentencias de a una en la pestaña SQL; cada una debe dar el error indicado).

**La app no repite estas reglas.** `iniciar.php` y `responder.php` solo llaman a `sp_iniciar_partida` y `sp_responder`; si la base rechaza algo, se muestra su mensaje.

---
