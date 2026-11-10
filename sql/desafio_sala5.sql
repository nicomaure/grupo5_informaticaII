-- =============================================================================
-- DESAFIO SALA 5 - Trivia por categorias, modos de juego y ranking
-- Proyecto "Una base de datos que se juega" - Informatica II - UNNE
-- Grupo Sala 5: Elias Aguero, Edgardo Molina, Nicolas Maure, Gabriel Martinez Canepa
--
-- Script unico (Hito 3): ejecutado sobre la base vacia deja todo listo.
--   1. Tablas independientes
--   2. Tablas dependientes (FK por id)
--   3. Reglas del juego impuestas en la base (triggers)
--   4. Vistas que alimentan las pantallas
--   5. Procedimientos con transacciones (acciones del juego)
--   6. Datos semilla
--   7. Transaccion demostrativa con ROLLBACK
--   8. Diez consultas con enunciado
--
-- Motor: MariaDB 10.6 o superior (probado en 10.11 / 11.x).
-- Como importarlo: phpMyAdmin > base grupo5 > Importar > este archivo.
-- (El usuario grupo5 no puede crear bases nuevas, por eso no hay
--  DROP/CREATE DATABASE: se trabaja dentro de la base grupo5.)
-- =============================================================================

USE grupo5;

SET NAMES utf8mb4;

-- Borrado previo para poder re-ejecutar el script sobre la misma base.
-- Se borra en orden inverso a las dependencias.
SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW IF EXISTS v_ranking;
DROP VIEW IF EXISTS v_resultado_partida;
DROP VIEW IF EXISTS v_pregunta_partida;
DROP VIEW IF EXISTS v_categoria_arbol;
DROP PROCEDURE IF EXISTS sp_iniciar_partida;
DROP PROCEDURE IF EXISTS sp_responder;
DROP TABLE IF EXISTS partida_pregunta;
DROP TABLE IF EXISTS partida;
DROP TABLE IF EXISTS opcion;
DROP TABLE IF EXISTS pregunta;
DROP TABLE IF EXISTS modo_juego;
DROP TABLE IF EXISTS dificultad;
DROP TABLE IF EXISTS categoria;
DROP TABLE IF EXISTS jugador;
SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================================
-- 1. TABLAS INDEPENDIENTES (sin claves foraneas hacia otras tablas)
-- =============================================================================

-- JUGADOR: quien juega. id es la PK artificial; el alias del juego queda UNIQUE.
CREATE TABLE jugador (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    alias      VARCHAR(30) NOT NULL UNIQUE,
    fecha_alta DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_jugador_alias CHECK (CHAR_LENGTH(TRIM(alias)) >= 3)
) ENGINE = InnoDB;

-- CATEGORIA: ESTRUCTURA AVANZADA -> RELACION REFLEXIVA 1:N.
-- Una categoria puede tener una categoria padre (Informatica > Bases de datos > SQL).
-- id_categoria_padre NULL = categoria raiz.
-- RESTRICT: no se borra una categoria que tiene subcategorias.
CREATE TABLE categoria (
    id                 INT AUTO_INCREMENT PRIMARY KEY,
    nombre             VARCHAR(60)  NOT NULL UNIQUE,
    descripcion        VARCHAR(200) NULL,
    id_categoria_padre INT          NULL,
    CONSTRAINT fk_categoria_padre FOREIGN KEY (id_categoria_padre)
        REFERENCES categoria (id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- DIFICULTAD: tabla propia para no repetir "puntos" en cada pregunta (3FN):
-- los puntos dependen de la dificultad, no de la pregunta.
CREATE TABLE dificultad (
    id     INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(20) NOT NULL UNIQUE,
    nivel  INT         NOT NULL UNIQUE,
    puntos INT         NOT NULL,
    CONSTRAINT chk_dificultad_nivel  CHECK (nivel BETWEEN 1 AND 5),
    CONSTRAINT chk_dificultad_puntos CHECK (puntos > 0)
) ENGINE = InnoDB;

-- MODO_JUEGO: define cuantas preguntas tiene una partida (Relampago, Clasico, Maraton).
CREATE TABLE modo_juego (
    id                 INT AUTO_INCREMENT PRIMARY KEY,
    nombre             VARCHAR(30)  NOT NULL UNIQUE,
    descripcion        VARCHAR(200) NOT NULL,
    cantidad_preguntas INT          NOT NULL,
    CONSTRAINT chk_modo_cantidad CHECK (cantidad_preguntas BETWEEN 3 AND 20)
) ENGINE = InnoDB;

-- =============================================================================
-- 2. TABLAS DEPENDIENTES (con claves foraneas por id)
-- =============================================================================

-- PREGUNTA: contenido del juego.
-- estado BORRADOR = se esta cargando (no sale en partidas).
-- estado ACTIVA   = lista para jugar (la base exige exactamente 1 opcion correcta).
-- RESTRICT hacia categoria y dificultad: no se pierden preguntas por un borrado.
-- ON UPDATE RESTRICT en TODAS las FK del script: los id son artificiales
--   (AUTO_INCREMENT) y nunca se cambian; si alguien intenta cambiar un id que
--   esta referenciado, la base lo rechaza en vez de propagarlo.
CREATE TABLE pregunta (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    enunciado     VARCHAR(255) NOT NULL UNIQUE,
    explicacion   VARCHAR(255) NULL,
    estado        VARCHAR(10)  NOT NULL DEFAULT 'BORRADOR',
    id_categoria  INT          NOT NULL,
    id_dificultad INT          NOT NULL,
    CONSTRAINT chk_pregunta_estado CHECK (estado IN ('BORRADOR', 'ACTIVA')),
    CONSTRAINT fk_pregunta_categoria FOREIGN KEY (id_categoria)
        REFERENCES categoria (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_pregunta_dificultad FOREIGN KEY (id_dificultad)
        REFERENCES dificultad (id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- OPCION: alternativas de cada pregunta (relacion 1:N "tiene").
-- CASCADE: las opciones pertenecen a su pregunta y se borran con ella.
-- UNIQUE (id_pregunta, texto): una pregunta no repite la misma opcion.
-- UNIQUE (id, id_pregunta): no agrega informacion nueva (id ya es unico), pero
--   permite que partida_pregunta use una FK COMPUESTA (opcion, pregunta) y asi
--   la base garantiza que la opcion elegida es de esa pregunta (regla R3).
CREATE TABLE opcion (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    id_pregunta INT          NOT NULL,
    texto       VARCHAR(150) NOT NULL,
    es_correcta TINYINT(1)   NOT NULL DEFAULT 0,
    CONSTRAINT chk_opcion_correcta CHECK (es_correcta IN (0, 1)),
    CONSTRAINT uq_opcion_pregunta_texto UNIQUE (id_pregunta, texto),
    CONSTRAINT uq_opcion_id_pregunta UNIQUE (id, id_pregunta),
    CONSTRAINT fk_opcion_pregunta FOREIGN KEY (id_pregunta)
        REFERENCES pregunta (id) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- PARTIDA: cada intento de un jugador, en un modo y una categoria.
-- El puntaje NO se guarda: se calcula en la vista v_resultado_partida a partir
-- de las respuestas (dato derivado -> evitarlo mantiene la 3FN y la regla R7).
-- CHECK emparejado: EN_CURSO sin fecha_fin / FINALIZADA con fecha_fin.
-- RESTRICT: no se borra un jugador, modo o categoria con historial de partidas.
CREATE TABLE partida (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    id_jugador    INT         NOT NULL,
    id_modo_juego INT         NOT NULL,
    id_categoria  INT         NOT NULL,
    estado        VARCHAR(12) NOT NULL DEFAULT 'EN_CURSO',
    fecha_inicio  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_fin     DATETIME    NULL,
    CONSTRAINT chk_partida_estado CHECK (estado IN ('EN_CURSO', 'FINALIZADA')),
    CONSTRAINT chk_partida_fin CHECK (
        (estado = 'EN_CURSO'   AND fecha_fin IS NULL) OR
        (estado = 'FINALIZADA' AND fecha_fin IS NOT NULL AND fecha_fin >= fecha_inicio)
    ),
    CONSTRAINT fk_partida_jugador FOREIGN KEY (id_jugador)
        REFERENCES jugador (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_partida_modo FOREIGN KEY (id_modo_juego)
        REFERENCES modo_juego (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_partida_categoria FOREIGN KEY (id_categoria)
        REFERENCES categoria (id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- PARTIDA_PREGUNTA: RELACION N:M CON ATRIBUTOS PROPIOS entre partida y pregunta.
-- Atributos de la relacion: orden en que sale la pregunta, opcion elegida y
-- fecha de respuesta (la respuesta dada pertenece a esta relacion).
-- UNIQUE (id_partida, id_pregunta): una pregunta no se repite en la partida (R1).
-- UNIQUE (id_partida, orden): no hay dos preguntas en la misma posicion.
-- FK compuesta (id_opcion_elegida, id_pregunta) -> opcion (id, id_pregunta):
--   la opcion elegida tiene que ser una opcion de ESA pregunta (R3).
-- CHECK emparejado: sin responder = las dos columnas NULL; respondida = las dos con valor.
-- CASCADE hacia partida (la relacion no existe sin la partida).
CREATE TABLE partida_pregunta (
    id                INT AUTO_INCREMENT PRIMARY KEY,
    id_partida        INT      NOT NULL,
    id_pregunta       INT      NOT NULL,
    orden             INT      NOT NULL,
    id_opcion_elegida INT      NULL,
    fecha_respuesta   DATETIME NULL,
    CONSTRAINT chk_pp_orden CHECK (orden > 0),
    CONSTRAINT chk_pp_respuesta CHECK (
        (id_opcion_elegida IS NULL     AND fecha_respuesta IS NULL) OR
        (id_opcion_elegida IS NOT NULL AND fecha_respuesta IS NOT NULL)
    ),
    CONSTRAINT uq_pp_partida_pregunta UNIQUE (id_partida, id_pregunta),
    CONSTRAINT uq_pp_partida_orden UNIQUE (id_partida, orden),
    CONSTRAINT fk_pp_partida FOREIGN KEY (id_partida)
        REFERENCES partida (id) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_pp_pregunta FOREIGN KEY (id_pregunta)
        REFERENCES pregunta (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_pp_opcion_de_pregunta FOREIGN KEY (id_opcion_elegida, id_pregunta)
        REFERENCES opcion (id, id_pregunta) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE = InnoDB;

-- =============================================================================
-- 3. REGLAS DEL JUEGO IMPUESTAS EN LA BASE (triggers)
-- Cada trigger rechaza la operacion con SIGNAL SQLSTATE '45000' y un mensaje
-- claro. La aplicacion PHP NO repite estas validaciones: solo muestra el mensaje.
-- =============================================================================

DELIMITER $$

-- R4a. Una pregunta nace en BORRADOR (todavia no tiene opciones cargadas).
CREATE TRIGGER trg_pregunta_bi
BEFORE INSERT ON pregunta
FOR EACH ROW
BEGIN
    IF NEW.estado = 'ACTIVA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R4: una pregunta se crea en BORRADOR y se activa cuando tiene sus opciones';
    END IF;
END$$

-- R4b. Para pasar a ACTIVA: al menos 2 opciones y EXACTAMENTE una correcta.
CREATE TRIGGER trg_pregunta_bu
BEFORE UPDATE ON pregunta
FOR EACH ROW
BEGIN
    IF NEW.estado = 'ACTIVA' THEN
        IF (SELECT COUNT(*) FROM opcion WHERE id_pregunta = NEW.id) < 2 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'R4: una pregunta ACTIVA necesita al menos 2 opciones';
        END IF;
        IF (SELECT COUNT(*) FROM opcion
             WHERE id_pregunta = NEW.id AND es_correcta = 1) <> 1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'R4: una pregunta ACTIVA debe tener exactamente una opcion correcta';
        END IF;
    END IF;
END$$

-- R4c. Las opciones de una pregunta ACTIVA quedan congeladas
-- (si no, se podria romper la regla "exactamente una correcta" despues de activarla).
CREATE TRIGGER trg_opcion_bi
BEFORE INSERT ON opcion
FOR EACH ROW
BEGIN
    IF (SELECT estado FROM pregunta WHERE id = NEW.id_pregunta) = 'ACTIVA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R4: no se agregan opciones a una pregunta ACTIVA (pasala a BORRADOR)';
    END IF;
END$$

CREATE TRIGGER trg_opcion_bu
BEFORE UPDATE ON opcion
FOR EACH ROW
BEGIN
    IF (SELECT estado FROM pregunta WHERE id = OLD.id_pregunta) = 'ACTIVA'
       OR (SELECT estado FROM pregunta WHERE id = NEW.id_pregunta) = 'ACTIVA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R4: no se modifican opciones de una pregunta ACTIVA (pasala a BORRADOR)';
    END IF;
END$$

CREATE TRIGGER trg_opcion_bd
BEFORE DELETE ON opcion
FOR EACH ROW
BEGIN
    IF (SELECT estado FROM pregunta WHERE id = OLD.id_pregunta) = 'ACTIVA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R4: no se borran opciones de una pregunta ACTIVA (pasala a BORRADOR)';
    END IF;
END$$

-- R5. Armado de la partida: solo en partidas EN_CURSO, solo preguntas ACTIVAS
-- y nunca mas preguntas (ni un orden mayor) que las que define el modo de juego.
CREATE TRIGGER trg_pp_bi
BEFORE INSERT ON partida_pregunta
FOR EACH ROW
BEGIN
    DECLARE v_estado   VARCHAR(12);
    DECLARE v_cantidad INT;

    SELECT p.estado, m.cantidad_preguntas
      INTO v_estado, v_cantidad
      FROM partida p
      JOIN modo_juego m ON m.id = p.id_modo_juego
     WHERE p.id = NEW.id_partida;

    IF v_estado <> 'EN_CURSO' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R5: no se agregan preguntas a una partida FINALIZADA';
    END IF;
    IF (SELECT estado FROM pregunta WHERE id = NEW.id_pregunta) <> 'ACTIVA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R5: solo las preguntas ACTIVAS pueden salir en una partida';
    END IF;
    IF NEW.orden > v_cantidad
       OR (SELECT COUNT(*) FROM partida_pregunta WHERE id_partida = NEW.id_partida) >= v_cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R5: la partida ya tiene todas las preguntas de su modo de juego';
    END IF;
END$$

-- R2. Una pregunta de la partida se responde UNA sola vez, y solo mientras la
-- partida esta EN_CURSO. Tampoco se puede cambiar que pregunta es ni su orden.
CREATE TRIGGER trg_pp_bu
BEFORE UPDATE ON partida_pregunta
FOR EACH ROW
BEGIN
    IF OLD.id_opcion_elegida IS NOT NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R2: esta pregunta ya fue respondida en la partida';
    END IF;
    IF NEW.id_partida <> OLD.id_partida OR NEW.id_pregunta <> OLD.id_pregunta
       OR NEW.orden <> OLD.orden THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R2: no se cambia la pregunta ni el orden de una partida';
    END IF;
    IF (SELECT estado FROM partida WHERE id = NEW.id_partida) <> 'EN_CURSO' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R2: no se responde en una partida FINALIZADA';
    END IF;
END$$

-- R6. Una partida solo se FINALIZA cuando tiene todas sus preguntas respondidas,
-- y una partida FINALIZADA ya no se modifica (el ranking no se puede "arreglar").
CREATE TRIGGER trg_partida_bu
BEFORE UPDATE ON partida
FOR EACH ROW
BEGIN
    IF OLD.estado = 'FINALIZADA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'R6: una partida FINALIZADA no se modifica';
    END IF;
    IF NEW.estado = 'FINALIZADA' THEN
        IF (SELECT COUNT(*) FROM partida_pregunta
             WHERE id_partida = NEW.id AND id_opcion_elegida IS NOT NULL)
           < (SELECT cantidad_preguntas FROM modo_juego WHERE id = NEW.id_modo_juego) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'R6: no se puede finalizar, faltan preguntas por responder';
        END IF;
    END IF;
END$$

DELIMITER ;

-- =============================================================================
-- 4. VISTAS (alimentan las pantallas del juego)
-- =============================================================================

-- v_categoria_arbol: pantalla de inicio (selector de categoria).
-- Recorre la relacion reflexiva con WITH RECURSIVE: arma la ruta completa
-- ("Informatica > Bases de datos > SQL") y cuenta las preguntas ACTIVAS de la
-- categoria MAS todas sus subcategorias.
CREATE VIEW v_categoria_arbol AS
WITH RECURSIVE
arbol (id, nombre, ruta, nivel) AS (
    SELECT id, nombre, CAST(nombre AS CHAR(300)), 1
      FROM categoria
     WHERE id_categoria_padre IS NULL
    UNION ALL
    SELECT c.id, c.nombre, CONCAT(a.ruta, ' > ', c.nombre), a.nivel + 1
      FROM categoria c
      JOIN arbol a ON c.id_categoria_padre = a.id
),
cierre (id_ancestro, id_descendiente) AS (
    SELECT id, id FROM categoria
    UNION ALL
    SELECT ci.id_ancestro, c.id
      FROM categoria c
      JOIN cierre ci ON c.id_categoria_padre = ci.id_descendiente
)
SELECT a.id,
       a.nombre,
       a.ruta,
       a.nivel,
       (SELECT COUNT(*)
          FROM cierre ci
          JOIN pregunta p ON p.id_categoria = ci.id_descendiente
         WHERE ci.id_ancestro = a.id
           AND p.estado = 'ACTIVA') AS preguntas_activas
  FROM arbol a;

-- v_pregunta_partida: pantalla de juego (estado de la partida pregunta por pregunta).
-- No expone cual es la opcion correcta de las preguntas pendientes:
-- es_correcta solo tiene valor cuando la pregunta ya fue respondida.
CREATE VIEW v_pregunta_partida AS
SELECT pp.id_partida,
       pp.orden,
       m.cantidad_preguntas AS total_preguntas,
       pr.id                AS id_pregunta,
       pr.enunciado,
       c.nombre             AS categoria,
       d.nombre             AS dificultad,
       d.puntos,
       pp.id_opcion_elegida,
       o.texto              AS opcion_elegida,
       o.es_correcta,
       CASE WHEN pp.id_opcion_elegida IS NULL THEN NULL ELSE pr.explicacion END AS explicacion,
       CASE WHEN pp.id_opcion_elegida IS NULL THEN NULL ELSE oc.texto END       AS opcion_correcta
  FROM partida_pregunta pp
  JOIN partida    p  ON p.id  = pp.id_partida
  JOIN modo_juego m  ON m.id  = p.id_modo_juego
  JOIN pregunta   pr ON pr.id = pp.id_pregunta
  JOIN categoria  c  ON c.id  = pr.id_categoria
  JOIN dificultad d  ON d.id  = pr.id_dificultad
  LEFT JOIN opcion o  ON o.id = pp.id_opcion_elegida
  LEFT JOIN opcion oc ON oc.id_pregunta = pr.id AND oc.es_correcta = 1;

-- v_resultado_partida: pantalla de resultado.
-- R7: el puntaje sale SOLO de las respuestas registradas (suma de los puntos de
-- la dificultad de cada pregunta respondida correctamente). No hay columna puntaje.
CREATE VIEW v_resultado_partida AS
SELECT p.id                 AS id_partida,
       j.id                 AS id_jugador,
       j.alias,
       m.nombre             AS modo,
       c.nombre             AS categoria,
       p.estado,
       p.fecha_inicio,
       p.fecha_fin,
       TIMESTAMPDIFF(SECOND, p.fecha_inicio, p.fecha_fin) AS duracion_seg,
       m.cantidad_preguntas AS total_preguntas,
       COUNT(pp.id_opcion_elegida)                        AS respondidas,
       COALESCE(SUM(o.es_correcta), 0)                    AS correctas,
       COALESCE(SUM(CASE WHEN o.es_correcta = 1 THEN d.puntos ELSE 0 END), 0) AS puntaje
  FROM partida p
  JOIN jugador    j ON j.id = p.id_jugador
  JOIN modo_juego m ON m.id = p.id_modo_juego
  JOIN categoria  c ON c.id = p.id_categoria
  LEFT JOIN partida_pregunta pp ON pp.id_partida = p.id
  LEFT JOIN pregunta   pr ON pr.id = pp.id_pregunta
  LEFT JOIN dificultad d  ON d.id  = pr.id_dificultad
  LEFT JOIN opcion     o  ON o.id  = pp.id_opcion_elegida
 GROUP BY p.id, j.id, j.alias, m.nombre, c.nombre, p.estado,
          p.fecha_inicio, p.fecha_fin, m.cantidad_preguntas;

-- v_ranking: pantalla de ranking. Solo partidas FINALIZADAS.
-- Desempate: a igual puntaje gana quien termino mas rapido.
CREATE VIEW v_ranking AS
SELECT RANK() OVER (ORDER BY r.puntaje DESC, r.duracion_seg ASC) AS puesto,
       r.id_partida,
       r.alias,
       r.modo,
       r.categoria,
       r.correctas,
       r.total_preguntas,
       r.puntaje,
       r.duracion_seg,
       r.fecha_fin
  FROM v_resultado_partida r
 WHERE r.estado = 'FINALIZADA';

-- =============================================================================
-- 5. PROCEDIMIENTOS CON TRANSACCIONES (acciones del juego)
-- La aplicacion llama a estos procedimientos; no arma las partidas ni calcula
-- puntajes por su cuenta.
-- =============================================================================

DELIMITER $$

-- ACCION "INICIAR PARTIDA" (atomica):
--   1) crea la partida
--   2) sortea N preguntas ACTIVAS de la categoria elegida y sus subcategorias
--   3) si no alcanzan para el modo -> ROLLBACK: no queda una partida a medias
-- Sin transaccion quedaria una partida "fantasma" con menos preguntas que su
-- modo, que nunca podria finalizarse (R6) y ensuciaria las consultas.
CREATE PROCEDURE sp_iniciar_partida(
    IN  p_id_jugador   INT,
    IN  p_id_modo      INT,
    IN  p_id_categoria INT,
    OUT p_id_partida   INT
)
BEGIN
    DECLARE v_cantidad INT DEFAULT NULL;
    DECLARE v_cargadas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_partida = NULL;
        RESIGNAL;
    END;

    SELECT cantidad_preguntas INTO v_cantidad
      FROM modo_juego WHERE id = p_id_modo;
    IF v_cantidad IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El modo de juego no existe';
    END IF;

    START TRANSACTION;

    INSERT INTO partida (id_jugador, id_modo_juego, id_categoria)
    VALUES (p_id_jugador, p_id_modo, p_id_categoria);
    SET p_id_partida = LAST_INSERT_ID();

    INSERT INTO partida_pregunta (id_partida, id_pregunta, orden)
    WITH RECURSIVE sub (id) AS (
        SELECT id FROM categoria WHERE id = p_id_categoria
        UNION ALL
        SELECT c.id FROM categoria c JOIN sub s ON c.id_categoria_padre = s.id
    )
    SELECT p_id_partida, elegidas.id, ROW_NUMBER() OVER (ORDER BY elegidas.azar)
      FROM (SELECT pr.id, RAND() AS azar
              FROM pregunta pr
              JOIN sub s ON s.id = pr.id_categoria
             WHERE pr.estado = 'ACTIVA'
             ORDER BY azar
             LIMIT v_cantidad) AS elegidas;

    SET v_cargadas = ROW_COUNT();

    IF v_cargadas < v_cantidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No hay suficientes preguntas activas en esa categoria para este modo de juego';
    END IF;

    COMMIT;
END$$

-- ACCION "RESPONDER" (atomica):
--   1) registra la opcion elegida (los triggers validan R2 y la FK compuesta R3)
--   2) si era la ultima pregunta, finaliza la partida (trigger R6)
-- Las dos cosas ocurren juntas o ninguna: sin transaccion podria quedar la
-- ultima respuesta guardada y la partida EN_CURSO para siempre (fuera del ranking).
CREATE PROCEDURE sp_responder(
    IN  p_id_partida  INT,
    IN  p_id_pregunta INT,
    IN  p_id_opcion   INT,
    OUT p_es_correcta TINYINT,
    OUT p_finalizada  TINYINT
)
BEGIN
    DECLARE v_estado VARCHAR(12) DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Bloquea la partida: dos clics simultaneos no pueden finalizarla dos veces.
    SELECT estado INTO v_estado FROM partida WHERE id = p_id_partida FOR UPDATE;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La partida no existe';
    END IF;

    UPDATE partida_pregunta
       SET id_opcion_elegida = p_id_opcion,
           fecha_respuesta   = NOW()
     WHERE id_partida = p_id_partida
       AND id_pregunta = p_id_pregunta;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Esa pregunta no pertenece a la partida';
    END IF;

    SELECT es_correcta INTO p_es_correcta FROM opcion WHERE id = p_id_opcion;

    IF NOT EXISTS (SELECT 1 FROM partida_pregunta
                    WHERE id_partida = p_id_partida AND id_opcion_elegida IS NULL) THEN
        UPDATE partida
           SET estado = 'FINALIZADA', fecha_fin = NOW()
         WHERE id = p_id_partida;
        SET p_finalizada = 1;
    ELSE
        SET p_finalizada = 0;
    END IF;

    COMMIT;
END$$

DELIMITER ;

-- =============================================================================
-- 6. DATOS SEMILLA
-- Primero las tablas independientes, luego las que tienen FK.
-- Los id se asignan solos desde 1 en el orden de insercion (las tablas se
-- acaban de crear), por eso las FK de abajo usan esos numeros.
-- =============================================================================

-- Categorias raiz (id 1-4) y subcategorias (id 5-13). SQL (8) es hija de
-- Bases de datos (6), que es hija de Informatica (1): tres niveles.
INSERT INTO categoria (nombre, descripcion, id_categoria_padre) VALUES
    ('Informática', 'Programación, bases de datos, redes y sistemas', NULL),
    ('Ciencia', 'Física, química y biología', NULL),
    ('Historia y Geografía', 'Argentina y el mundo', NULL),
    ('Deportes', 'Preguntas deportivas', NULL),
    ('Programación', 'Lógica, variables y estructuras de control', 1),
    ('Bases de datos', 'Modelado, normalización y transacciones', 1),
    ('Redes y Linux', 'Comandos, puertos y protocolos', 1),
    ('SQL', 'Consultas y sentencias SQL', 6),
    ('Física', 'Electricidad, mecánica y luz', 2),
    ('Biología y Química', 'Seres vivos y elementos', 2),
    ('Historia argentina', 'Hechos y protagonistas', 3),
    ('Geografía', 'Lugares, ríos y capitales', 3),
    ('Fútbol', 'Reglas y mundiales', 4);

-- Dificultades: id 1=Fácil, 2=Media, 3=Difícil
INSERT INTO dificultad (nombre, nivel, puntos) VALUES
    ('Fácil', 1, 10),
    ('Media', 2, 20),
    ('Difícil', 3, 30);

-- Modos: id 1=Relámpago (5), 2=Clásico (10), 3=Maratón (15)
INSERT INTO modo_juego (nombre, descripcion, cantidad_preguntas) VALUES
    ('Relámpago', '5 preguntas rápidas para una partida corta', 5),
    ('Clásico', 'La partida estándar de 10 preguntas', 10),
    ('Maratón', '15 preguntas para los que saben mucho', 15);

-- Jugadores: id 1..15
INSERT INTO jugador (alias, fecha_alta) VALUES
    ('EliasA', '2026-10-14 09:00:00'),
    ('Edgardo_M', '2026-10-15 09:00:00'),
    ('NicoMaure', '2026-10-16 09:00:00'),
    ('GabiMC', '2026-10-17 09:00:00'),
    ('LaProfe', '2026-10-18 09:00:00'),
    ('Byte_Master', '2026-10-19 09:00:00'),
    ('Ana_Quiz', '2026-10-20 09:00:00'),
    ('Tincho22', '2026-10-21 09:00:00'),
    ('SofiDev', '2026-10-22 09:00:00'),
    ('Lucas_SQL', '2026-10-23 09:00:00'),
    ('Mica3FN', '2026-10-24 09:00:00'),
    ('JuanchoPHP', '2026-10-25 09:00:00'),
    ('Rocio_Linux', '2026-10-26 09:00:00'),
    ('Fede_Trivia', '2026-10-27 09:00:00'),
    ('ValeNeuquen', '2026-10-28 09:00:00');

-- Preguntas: se cargan en BORRADOR (la base no deja crearlas ACTIVAS).
-- id 1..55 = preguntas jugables; id 56..57 = quedan en borrador.
INSERT INTO pregunta (enunciado, explicacion, id_categoria, id_dificultad) VALUES
    ('¿Qué símbolo inicia el nombre de una variable en PHP?', 'En PHP toda variable empieza con $, por ejemplo $puntaje.', 5, 1),
    ('¿Qué estructura repite un bloque mientras se cumpla una condición?', 'while evalúa la condición antes de cada vuelta del ciclo.', 5, 1),
    ('En Python, ¿qué función muestra un texto en pantalla?', 'print() es la función de salida estándar de Python.', 5, 1),
    ('¿Qué tipo de dato guarda solo verdadero o falso?', 'El tipo booleano solo admite dos valores: true o false.', 5, 1),
    ('¿Cuánto da 7 % 3 (resto de la división)?', '7 dividido 3 da 2 y sobra 1; el operador % devuelve ese resto.', 5, 2),
    ('¿Cómo se llama una función que se llama a sí misma?', 'Una función recursiva se invoca a sí misma hasta llegar a un caso base.', 5, 2),
    ('¿Cuál es la complejidad de la búsqueda binaria en un arreglo ordenado?', 'En cada paso descarta la mitad de los elementos, por eso es logarítmica.', 5, 3),
    ('¿Qué identifica de forma única cada fila de una tabla?', 'La clave primaria (PK) no se repite ni puede ser NULL.', 6, 1),
    ('Al pasar al modelo relacional, una relación N:M se transforma en...', 'La N:M genera una tabla con las FK de ambas entidades, como partida_pregunta.', 6, 2),
    ('¿Qué forma normal elimina las dependencias transitivas?', 'En 3FN ningún atributo no clave depende de otro atributo no clave.', 6, 2),
    ('¿Qué propiedad ACID asegura que una transacción ocurre completa o no ocurre?', 'Atomicidad: todas las operaciones se confirman juntas o se deshacen juntas.', 6, 2),
    ('¿Cómo se llama la relación de una entidad consigo misma?', 'En este juego, categoría es reflexiva: una categoría tiene una categoría padre.', 6, 2),
    ('¿Qué motor de almacenamiento de MariaDB soporta claves foráneas y transacciones?', 'InnoDB es el motor transaccional que respeta las claves foráneas.', 6, 3),
    ('¿Qué sentencia se usa para consultar datos?', 'SELECT lee datos; las otras tres los modifican.', 8, 1),
    ('¿Qué devuelve COUNT(*)?', 'COUNT(*) cuenta filas; SUM, MAX y AVG hacen las otras operaciones.', 8, 1),
    ('¿Qué restricción impide valores repetidos en una columna?', 'UNIQUE rechaza cualquier valor que ya exista en esa columna.', 8, 1),
    ('¿Qué cláusula filtra grupos después de un GROUP BY?', 'WHERE filtra filas antes de agrupar; HAVING filtra los grupos.', 8, 2),
    ('¿Qué JOIN devuelve todas las filas de la tabla izquierda aunque no tengan pareja?', 'LEFT JOIN completa con NULL; así se arma un anti-join con IS NULL.', 8, 2),
    ('¿Qué sentencia deshace los cambios de una transacción no confirmada?', 'ROLLBACK vuelve atrás todo lo hecho desde START TRANSACTION.', 8, 2),
    ('¿Qué sentencia agrega una columna a una tabla que ya existe?', 'ALTER TABLE ... ADD COLUMN cambia la estructura de la tabla.', 8, 3),
    ('¿Qué comando de Linux lista los archivos de una carpeta?', 'ls lista; cd cambia de carpeta; pwd muestra la actual; rm borra.', 7, 1),
    ('¿Qué comando muestra la carpeta en la que estás parado?', 'pwd significa print working directory.', 7, 1),
    ('En Ubuntu, ¿qué comando ejecuta otro comando como administrador?', 'sudo ejecuta un comando con privilegios de superusuario.', 7, 1),
    ('¿Qué puerto usa HTTPS por defecto?', '80 es HTTP, 22 es SSH y 3306 es MariaDB/MySQL.', 7, 2),
    ('¿Qué puerto usa MariaDB por defecto?', '3306 es el puerto clásico de MySQL y MariaDB; 5432 es PostgreSQL.', 7, 2),
    ('¿Qué protocolo traduce nombres de dominio a direcciones IP?', 'DNS resuelve nombres como azure.com a una IP.', 7, 2),
    ('¿Qué comando cambia los permisos de un archivo?', 'chmod cambia permisos; chown cambia el dueño.', 7, 3),
    ('¿Cuál es la unidad de fuerza en el Sistema Internacional?', 'La fuerza se mide en newtons (N).', 9, 1),
    ('¿En qué unidad se mide la resistencia eléctrica?', 'La resistencia se mide en ohms (Ω).', 9, 1),
    ('Por la ley de Ohm, si V = 12 V y R = 4 Ω, ¿cuánto vale la corriente?', 'I = V / R = 12 / 4 = 3 A.', 9, 2),
    ('¿Qué magnitud se mide en watts?', 'El watt mide potencia: energía por unidad de tiempo.', 9, 2),
    ('¿A qué velocidad aproximada viaja la luz en el vacío?', 'La luz recorre unos 300.000 km por segundo.', 9, 2),
    ('Dos resistencias de 6 Ω conectadas en paralelo equivalen a...', 'Dos resistencias iguales en paralelo equivalen a la mitad: 6 / 2 = 3 Ω.', 9, 3),
    ('¿Cuál es el símbolo químico del oxígeno?', 'El oxígeno es O; Os es el osmio.', 10, 1),
    ('¿Qué gas absorben las plantas para hacer la fotosíntesis?', 'Las plantas toman CO₂ y liberan oxígeno.', 10, 1),
    ('¿Qué orgánulo produce la mayor parte de la energía (ATP) de la célula?', 'La respiración celular ocurre principalmente en la mitocondria.', 10, 2),
    ('¿Cuántos cromosomas tiene normalmente una célula humana?', 'Son 23 pares: 46 cromosomas.', 10, 2),
    ('¿Cuál es el pH del agua pura a 25 °C?', 'El agua pura es neutra: pH 7.', 10, 2),
    ('¿Cuál es el símbolo químico del sodio?', 'Na viene del latín natrium; S es el azufre.', 10, 3),
    ('¿En qué año se declaró la independencia argentina?', 'El 9 de julio de 1816; en 1810 fue la Revolución de Mayo.', 11, 1),
    ('¿En qué ciudad se declaró la independencia?', 'El Congreso sesionó en la Casa Histórica de Tucumán.', 11, 1),
    ('¿Quién creó la bandera argentina?', 'Belgrano la izó por primera vez en Rosario en 1812.', 11, 1),
    ('¿En qué año se sancionó la Constitución Nacional?', 'La Constitución se sancionó en 1853 en Santa Fe.', 11, 2),
    ('¿En qué provincia se organizó el Ejército de los Andes?', 'San Martín lo organizó en el campamento de El Plumerillo, Mendoza.', 11, 2),
    ('¿Durante qué presidencia se sancionó la Ley 1420 de educación común?', 'Se sancionó en 1884, durante la primera presidencia de Roca.', 11, 3),
    ('¿Cuál es la montaña más alta de América?', 'El Aconcagua, en Mendoza, supera los 6.900 metros.', 12, 1),
    ('¿Cuál es la capital de la provincia de Neuquén?', 'La capital es la ciudad de Neuquén; Cipolletti está en Río Negro.', 12, 1),
    ('¿Cuál es la capital de la provincia del Chaco?', 'Resistencia es la capital del Chaco, frente a Corrientes.', 12, 2),
    ('¿Cuál es el río más largo de Sudamérica?', 'El Amazonas es el río más largo y caudaloso de Sudamérica.', 12, 2),
    ('¿Cuántas provincias tiene la Argentina?', 'Son 23 provincias más la Ciudad Autónoma de Buenos Aires.', 12, 3),
    ('¿Cuántos jugadores por equipo hay en la cancha en un partido de fútbol?', 'Cada equipo juega con 11, incluido el arquero.', 13, 1),
    ('¿En qué país se jugó el Mundial 2022?', 'El Mundial 2022 se jugó en Qatar y lo ganó Argentina.', 13, 1),
    ('¿Cuánto dura un partido reglamentario, sin tiempo adicional?', 'Dos tiempos de 45 minutos.', 13, 1),
    ('¿En qué año ganó Argentina su primer Mundial?', 'El primero fue en 1978; después 1986 y 2022.', 13, 2),
    ('¿Cuántos Mundiales había ganado Argentina hasta Qatar 2022 inclusive?', '1978, 1986 y 2022.', 13, 2),
    ('¿Cuál es el océano más grande del planeta?', 'Pregunta en carga: todavía no tiene marcada la opción correcta.', 12, 2),
    ('¿Qué selección ganó más Mundiales?', 'Pregunta en carga: tiene dos opciones marcadas como correctas por error.', 13, 3);

-- Opciones: 4 por pregunta jugable (id 1..220), en orden mezclado.
INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
    (1, '$', 1),
    (1, '#', 0),
    (1, '&', 0),
    (1, '@', 0),
    (2, 'switch', 0),
    (2, 'return', 0),
    (2, 'if', 0),
    (2, 'while', 1),
    (3, 'echo()', 0),
    (3, 'write()', 0),
    (3, 'console()', 0),
    (3, 'print()', 1),
    (4, 'Flotante', 0),
    (4, 'Booleano', 1),
    (4, 'Entero', 0),
    (4, 'Cadena', 0),
    (5, '2', 0),
    (5, '1', 1),
    (5, '0', 0),
    (5, '3', 0),
    (6, 'Abstracta', 0),
    (6, 'Estática', 0),
    (6, 'Recursiva', 1),
    (6, 'Anónima', 0),
    (7, 'O(n²)', 0),
    (7, 'O(log n)', 1),
    (7, 'O(n)', 0),
    (7, 'O(1)', 0),
    (8, 'La clave foránea', 0),
    (8, 'Un índice secundario', 0),
    (8, 'La clave primaria', 1),
    (8, 'Una vista', 0),
    (9, 'Una tabla intermedia', 1),
    (9, 'Un trigger', 0),
    (9, 'Una vista', 0),
    (9, 'Un atributo multivaluado', 0),
    (10, 'Ninguna', 0),
    (10, '2FN', 0),
    (10, '3FN', 1),
    (10, '1FN', 0),
    (11, 'Consistencia', 0),
    (11, 'Aislamiento', 0),
    (11, 'Durabilidad', 0),
    (11, 'Atomicidad', 1),
    (12, 'Débil', 0),
    (12, 'Derivada', 0),
    (12, 'Reflexiva', 1),
    (12, 'Ternaria', 0),
    (13, 'MyISAM', 0),
    (13, 'MEMORY', 0),
    (13, 'InnoDB', 1),
    (13, 'CSV', 0),
    (14, 'DELETE', 0),
    (14, 'SELECT', 1),
    (14, 'UPDATE', 0),
    (14, 'INSERT', 0),
    (15, 'El valor máximo', 0),
    (15, 'La cantidad de filas', 1),
    (15, 'La suma de una columna', 0),
    (15, 'El promedio', 0),
    (16, 'NOT NULL', 0),
    (16, 'UNIQUE', 1),
    (16, 'CHECK', 0),
    (16, 'DEFAULT', 0),
    (17, 'ORDER BY', 0),
    (17, 'HAVING', 1),
    (17, 'LIMIT', 0),
    (17, 'WHERE', 0),
    (18, 'CROSS JOIN', 0),
    (18, 'LEFT JOIN', 1),
    (18, 'INNER JOIN', 0),
    (18, 'RIGHT JOIN', 0),
    (19, 'REVERT', 0),
    (19, 'COMMIT', 0),
    (19, 'ROLLBACK', 1),
    (19, 'SAVE', 0),
    (20, 'ALTER TABLE', 1),
    (20, 'INSERT COLUMN', 0),
    (20, 'UPDATE TABLE', 0),
    (20, 'MODIFY TABLE', 0),
    (21, 'rm', 0),
    (21, 'cd', 0),
    (21, 'ls', 1),
    (21, 'pwd', 0),
    (22, 'ls', 0),
    (22, 'pwd', 1),
    (22, 'whoami', 0),
    (22, 'cat', 0),
    (23, 'apt', 0),
    (23, 'passwd', 0),
    (23, 'chown', 0),
    (23, 'sudo', 1),
    (24, '3306', 0),
    (24, '443', 1),
    (24, '80', 0),
    (24, '22', 0),
    (25, '3306', 1),
    (25, '8080', 0),
    (25, '5432', 0),
    (25, '21', 0),
    (26, 'FTP', 0),
    (26, 'SMTP', 0),
    (26, 'DHCP', 0),
    (26, 'DNS', 1),
    (27, 'grep', 0),
    (27, 'chmod', 1),
    (27, 'mv', 0),
    (27, 'chown', 0),
    (28, 'Watt', 0),
    (28, 'Joule', 0),
    (28, 'Pascal', 0),
    (28, 'Newton', 1),
    (29, 'Ohm', 1),
    (29, 'Volt', 0),
    (29, 'Faraday', 0),
    (29, 'Ampere', 0),
    (30, '16 A', 0),
    (30, '3 A', 1),
    (30, '48 A', 0),
    (30, '8 A', 0),
    (31, 'Tensión', 0),
    (31, 'Potencia', 1),
    (31, 'Energía', 0),
    (31, 'Carga eléctrica', 0),
    (32, '30.000 km/s', 0),
    (32, '3.000 km/s', 0),
    (32, '300.000 km/s', 1),
    (32, '300 km/s', 0),
    (33, '3 Ω', 1),
    (33, '12 Ω', 0),
    (33, '36 Ω', 0),
    (33, '6 Ω', 0),
    (34, 'O', 1),
    (34, 'Og', 0),
    (34, 'Os', 0),
    (34, 'Ox', 0),
    (35, 'Helio', 0),
    (35, 'Nitrógeno', 0),
    (35, 'Oxígeno', 0),
    (35, 'Dióxido de carbono', 1),
    (36, 'Ribosoma', 0),
    (36, 'Aparato de Golgi', 0),
    (36, 'Mitocondria', 1),
    (36, 'Núcleo', 0),
    (37, '46', 1),
    (37, '44', 0),
    (37, '48', 0),
    (37, '23', 0),
    (38, '0', 0),
    (38, '14', 0),
    (38, '7', 1),
    (38, '5', 0),
    (39, 'S', 0),
    (39, 'So', 0),
    (39, 'Sd', 0),
    (39, 'Na', 1),
    (40, '1853', 0),
    (40, '1810', 0),
    (40, '1806', 0),
    (40, '1816', 1),
    (41, 'San Miguel de Tucumán', 1),
    (41, 'Mendoza', 0),
    (41, 'Buenos Aires', 0),
    (41, 'Córdoba', 0),
    (42, 'Mariano Moreno', 0),
    (42, 'Domingo F. Sarmiento', 0),
    (42, 'Manuel Belgrano', 1),
    (42, 'José de San Martín', 0),
    (43, '1880', 0),
    (43, '1853', 1),
    (43, '1816', 0),
    (43, '1912', 0),
    (44, 'Córdoba', 0),
    (44, 'Mendoza', 1),
    (44, 'Salta', 0),
    (44, 'San Juan', 0),
    (45, 'Domingo F. Sarmiento', 0),
    (45, 'Bartolomé Mitre', 0),
    (45, 'Julio A. Roca', 1),
    (45, 'Nicolás Avellaneda', 0),
    (46, 'Chimborazo', 0),
    (46, 'Aconcagua', 1),
    (46, 'Ojos del Salado', 0),
    (46, 'Fitz Roy', 0),
    (47, 'San Martín de los Andes', 0),
    (47, 'Cipolletti', 0),
    (47, 'Zapala', 0),
    (47, 'Neuquén', 1),
    (48, 'Formosa', 0),
    (48, 'Resistencia', 1),
    (48, 'Posadas', 0),
    (48, 'Corrientes', 0),
    (49, 'Amazonas', 1),
    (49, 'Orinoco', 0),
    (49, 'Paraná', 0),
    (49, 'Uruguay', 0),
    (50, '23', 1),
    (50, '22', 0),
    (50, '24', 0),
    (50, '25', 0),
    (51, '9', 0),
    (51, '11', 1),
    (51, '10', 0),
    (51, '12', 0),
    (52, 'Brasil', 0),
    (52, 'Japón', 0),
    (52, 'Rusia', 0),
    (52, 'Qatar', 1),
    (53, '100 minutos', 0),
    (53, '90 minutos', 1),
    (53, '80 minutos', 0),
    (53, '120 minutos', 0),
    (54, '2022', 0),
    (54, '1930', 0),
    (54, '1986', 0),
    (54, '1978', 1),
    (55, '4', 0),
    (55, '2', 0),
    (55, '3', 1),
    (55, '1', 0),
    (56, 'Pacífico', 0),
    (56, 'Atlántico', 0),
    (57, 'Brasil', 1),
    (57, 'Alemania', 1),
    (57, 'Italia', 0);

-- Activacion: el trigger trg_pregunta_bu verifica que cada una tenga
-- exactamente una opcion correcta. Las 2 preguntas en borrador NO se activan
-- (una no tiene correcta y otra tiene dos): ver pruebas_reglas.sql.
UPDATE pregunta SET estado = 'ACTIVA' WHERE id BETWEEN 1 AND 55;

-- Partidas simuladas: se cargan igual que en el juego real, respetando las
-- reglas: 1) partida EN_CURSO, 2) sus preguntas (con la respuesta dada),
-- 3) se finaliza (el trigger trg_partida_bu controla que este todo respondido).
-- La ultima (id 19) queda EN_CURSO a mitad de juego.

-- Partida 1: jugador 1, modo 3, categoria 1
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (1, 3, 1, '2026-10-20 18:00:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (1, 19, 1, 75, '2026-10-20 18:00:16'),
    (1, 23, 2, 89, '2026-10-20 18:00:38'),
    (1, 24, 3, 95, '2026-10-20 18:00:55'),
    (1, 14, 4, 54, '2026-10-20 18:01:10'),
    (1, 25, 5, 97, '2026-10-20 18:01:29'),
    (1, 10, 6, 39, '2026-10-20 18:01:53'),
    (1, 26, 7, 104, '2026-10-20 18:02:12'),
    (1, 16, 8, 64, '2026-10-20 18:02:35'),
    (1, 21, 9, 83, '2026-10-20 18:02:49'),
    (1, 6, 10, 23, '2026-10-20 18:02:55'),
    (1, 20, 11, 77, '2026-10-20 18:03:19'),
    (1, 17, 12, 66, '2026-10-20 18:03:30'),
    (1, 27, 13, 106, '2026-10-20 18:03:41'),
    (1, 9, 14, 34, '2026-10-20 18:03:48'),
    (1, 18, 15, 70, '2026-10-20 18:03:59');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-20 18:04:02' WHERE id = 1;

-- Partida 2: jugador 2, modo 1, categoria 1
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (2, 1, 1, '2026-10-21 21:17:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (2, 5, 1, 18, '2026-10-21 21:17:12'),
    (2, 4, 2, 14, '2026-10-21 21:17:31'),
    (2, 12, 3, 47, '2026-10-21 21:17:49'),
    (2, 6, 4, 23, '2026-10-21 21:17:57'),
    (2, 18, 5, 70, '2026-10-21 21:18:10');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-21 21:18:13' WHERE id = 2;

-- Partida 3: jugador 3, modo 2, categoria 2
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (3, 2, 2, '2026-10-23 00:34:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (3, 34, 1, 133, '2026-10-23 00:34:09'),
    (3, 28, 2, 112, '2026-10-23 00:34:31'),
    (3, 39, 3, 156, '2026-10-23 00:34:55'),
    (3, 35, 4, 138, '2026-10-23 00:35:12'),
    (3, 30, 5, 120, '2026-10-23 00:35:31'),
    (3, 31, 6, 122, '2026-10-23 00:35:54'),
    (3, 38, 7, 151, '2026-10-23 00:36:04'),
    (3, 36, 8, 143, '2026-10-23 00:36:22'),
    (3, 32, 9, 128, '2026-10-23 00:36:34'),
    (3, 29, 10, 113, '2026-10-23 00:36:42');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-23 00:36:45' WHERE id = 3;

-- Partida 4: jugador 4, modo 1, categoria 3
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (4, 1, 3, '2026-10-23 20:51:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (4, 40, 1, 160, '2026-10-23 20:51:25'),
    (4, 47, 2, 187, '2026-10-23 20:51:41'),
    (4, 41, 3, 161, '2026-10-23 20:51:59'),
    (4, 42, 4, 167, '2026-10-23 20:52:12'),
    (4, 44, 5, 175, '2026-10-23 20:52:33');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-23 20:52:36' WHERE id = 4;

-- Partida 5: jugador 5, modo 1, categoria 5
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (5, 1, 5, '2026-10-24 23:08:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (5, 4, 1, 14, '2026-10-24 23:08:21'),
    (5, 2, 2, 8, '2026-10-24 23:08:27'),
    (5, 3, 3, 12, '2026-10-24 23:08:42'),
    (5, 6, 4, 23, '2026-10-24 23:08:57'),
    (5, 5, 5, 18, '2026-10-24 23:09:03');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-24 23:09:06' WHERE id = 5;

-- Partida 6: jugador 6, modo 1, categoria 6
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (6, 1, 6, '2026-10-25 19:25:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (6, 18, 1, 69, '2026-10-25 19:25:10'),
    (6, 16, 2, 63, '2026-10-25 19:25:31'),
    (6, 11, 3, 41, '2026-10-25 19:25:44'),
    (6, 12, 4, 47, '2026-10-25 19:25:57'),
    (6, 8, 5, 30, '2026-10-25 19:26:07');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-25 19:26:10' WHERE id = 6;

-- Partida 7: jugador 7, modo 1, categoria 7
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (7, 1, 7, '2026-10-26 22:42:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (7, 23, 1, 89, '2026-10-26 22:42:25'),
    (7, 24, 2, 95, '2026-10-26 22:42:31'),
    (7, 25, 3, 97, '2026-10-26 22:42:46'),
    (7, 26, 4, 104, '2026-10-26 22:43:02'),
    (7, 27, 5, 106, '2026-10-26 22:43:24');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-26 22:43:27' WHERE id = 7;

-- Partida 8: jugador 8, modo 1, categoria 8
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (8, 1, 8, '2026-10-27 18:59:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (8, 16, 1, 62, '2026-10-27 18:59:06'),
    (8, 20, 2, 77, '2026-10-27 18:59:26'),
    (8, 18, 3, 72, '2026-10-27 18:59:35'),
    (8, 15, 4, 58, '2026-10-27 18:59:47'),
    (8, 14, 5, 54, '2026-10-27 19:00:06');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-27 19:00:09' WHERE id = 8;

-- Partida 9: jugador 9, modo 1, categoria 9
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (9, 1, 9, '2026-10-28 21:16:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (9, 31, 1, 122, '2026-10-28 21:16:15'),
    (9, 32, 2, 127, '2026-10-28 21:16:23'),
    (9, 29, 3, 113, '2026-10-28 21:16:29'),
    (9, 30, 4, 118, '2026-10-28 21:16:48'),
    (9, 28, 5, 109, '2026-10-28 21:17:09');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-28 21:17:12' WHERE id = 9;

-- Partida 10: jugador 10, modo 1, categoria 11
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (10, 1, 11, '2026-10-30 00:33:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (10, 41, 1, 161, '2026-10-30 00:33:23'),
    (10, 43, 2, 169, '2026-10-30 00:33:47'),
    (10, 42, 3, 166, '2026-10-30 00:33:55'),
    (10, 44, 4, 176, '2026-10-30 00:34:03'),
    (10, 40, 5, 160, '2026-10-30 00:34:09');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-30 00:34:12' WHERE id = 10;

-- Partida 11: jugador 11, modo 1, categoria 12
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (11, 1, 12, '2026-10-30 20:50:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (11, 49, 1, 193, '2026-10-30 20:50:09'),
    (11, 46, 2, 182, '2026-10-30 20:50:22'),
    (11, 47, 3, 188, '2026-10-30 20:50:31'),
    (11, 48, 4, 192, '2026-10-30 20:50:41'),
    (11, 50, 5, 197, '2026-10-30 20:51:01');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-30 20:51:04' WHERE id = 11;

-- Partida 12: jugador 12, modo 1, categoria 13
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (12, 1, 13, '2026-10-31 23:07:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (12, 55, 1, 219, '2026-10-31 23:07:25'),
    (12, 52, 2, 208, '2026-10-31 23:07:48'),
    (12, 54, 3, 214, '2026-10-31 23:08:06'),
    (12, 51, 4, 202, '2026-10-31 23:08:13'),
    (12, 53, 5, 212, '2026-10-31 23:08:22');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-31 23:08:25' WHERE id = 12;

-- Partida 13: jugador 13, modo 3, categoria 1
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (13, 3, 1, '2026-10-20 19:24:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (13, 5, 1, 18, '2026-10-20 19:24:10'),
    (13, 1, 2, 1, '2026-10-20 19:24:32'),
    (13, 16, 3, 62, '2026-10-20 19:24:55'),
    (13, 3, 4, 12, '2026-10-20 19:25:08'),
    (13, 12, 5, 47, '2026-10-20 19:25:31'),
    (13, 22, 6, 86, '2026-10-20 19:25:46'),
    (13, 18, 7, 71, '2026-10-20 19:25:56'),
    (13, 21, 8, 81, '2026-10-20 19:26:16'),
    (13, 14, 9, 56, '2026-10-20 19:26:26'),
    (13, 19, 10, 75, '2026-10-20 19:26:42'),
    (13, 17, 11, 66, '2026-10-20 19:26:49'),
    (13, 26, 12, 104, '2026-10-20 19:26:58'),
    (13, 24, 13, 94, '2026-10-20 19:27:18'),
    (13, 20, 14, 77, '2026-10-20 19:27:38'),
    (13, 27, 15, 106, '2026-10-20 19:27:54');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-20 19:27:57' WHERE id = 13;

-- Partida 14: jugador 14, modo 1, categoria 3
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (14, 1, 3, '2026-10-21 22:41:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (14, 49, 1, 194, '2026-10-21 22:41:19'),
    (14, 40, 2, 160, '2026-10-21 22:41:28'),
    (14, 47, 3, 185, '2026-10-21 22:41:49'),
    (14, 50, 4, 198, '2026-10-21 22:42:14'),
    (14, 41, 5, 161, '2026-10-21 22:42:29');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-21 22:42:32' WHERE id = 14;

-- Partida 15: jugador 15, modo 2, categoria 2
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (15, 2, 2, '2026-10-22 18:58:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (15, 38, 1, 151, '2026-10-22 18:58:17'),
    (15, 34, 2, 134, '2026-10-22 18:58:41'),
    (15, 35, 3, 140, '2026-10-22 18:58:52'),
    (15, 37, 4, 145, '2026-10-22 18:59:01'),
    (15, 29, 5, 113, '2026-10-22 18:59:12'),
    (15, 39, 6, 156, '2026-10-22 18:59:19'),
    (15, 30, 7, 118, '2026-10-22 18:59:40'),
    (15, 32, 8, 127, '2026-10-22 18:59:57'),
    (15, 31, 9, 122, '2026-10-22 19:00:18'),
    (15, 36, 10, 142, '2026-10-22 19:00:43');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-22 19:00:46' WHERE id = 15;

-- Partida 16: jugador 1, modo 1, categoria 6
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (1, 1, 6, '2026-10-23 21:15:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (16, 16, 1, 62, '2026-10-23 21:15:11'),
    (16, 20, 2, 79, '2026-10-23 21:15:29'),
    (16, 9, 3, 34, '2026-10-23 21:15:39'),
    (16, 11, 4, 42, '2026-10-23 21:15:53'),
    (16, 10, 5, 39, '2026-10-23 21:16:06');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-23 21:16:09' WHERE id = 16;

-- Partida 17: jugador 2, modo 1, categoria 10
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (2, 1, 10, '2026-10-25 00:32:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (17, 34, 1, 133, '2026-10-25 00:32:06'),
    (17, 36, 2, 141, '2026-10-25 00:32:27'),
    (17, 38, 3, 150, '2026-10-25 00:32:36'),
    (17, 35, 4, 140, '2026-10-25 00:32:51'),
    (17, 39, 5, 156, '2026-10-25 00:33:04');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-25 00:33:07' WHERE id = 17;

-- Partida 18: jugador 3, modo 1, categoria 1
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (3, 1, 1, '2026-10-25 20:49:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (18, 6, 1, 23, '2026-10-25 20:49:24'),
    (18, 2, 2, 8, '2026-10-25 20:49:32'),
    (18, 8, 3, 29, '2026-10-25 20:49:49'),
    (18, 25, 4, 97, '2026-10-25 20:50:09'),
    (18, 1, 5, 4, '2026-10-25 20:50:17');
UPDATE partida SET estado = 'FINALIZADA', fecha_fin = '2026-10-25 20:50:20' WHERE id = 18;

-- Partida 19: jugador 3, modo 1, categoria 1
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria, fecha_inicio) VALUES
    (3, 1, 1, '2026-10-26 23:06:00');
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden, id_opcion_elegida, fecha_respuesta) VALUES
    (19, 17, 1, 68, '2026-10-26 23:06:12'),
    (19, 6, 2, 23, '2026-10-26 23:06:37'),
    (19, 27, 3, NULL, NULL),
    (19, 9, 4, NULL, NULL),
    (19, 24, 5, NULL, NULL);

-- =============================================================================
-- 7. TRANSACCION DEMOSTRATIVA CON ROLLBACK
-- Es la misma accion "iniciar partida" que hace sp_iniciar_partida, escrita a
-- mano para mostrar el ROLLBACK paso a paso.
-- Caso: NicoMaure (jugador 3) quiere un Clasico (10 preguntas) de Futbol, pero
-- Futbol solo tiene 5 preguntas activas -> la partida no puede quedar a medias.
-- =============================================================================

SELECT COUNT(*) AS partidas_antes FROM partida;

START TRANSACTION;

-- Paso 1: se crea la partida
INSERT INTO partida (id_jugador, id_modo_juego, id_categoria) VALUES (3, 2, 13);
SET @id_partida_demo = LAST_INSERT_ID();

-- Paso 2: se cargan las preguntas activas de Futbol (solo hay 5 de las 10 necesarias)
INSERT INTO partida_pregunta (id_partida, id_pregunta, orden)
SELECT @id_partida_demo, pr.id, ROW_NUMBER() OVER (ORDER BY pr.id)
  FROM pregunta pr
 WHERE pr.id_categoria = 13 AND pr.estado = 'ACTIVA';

-- Paso 3: se controla. Faltan preguntas: la partida nunca podria finalizarse
-- (R6) y quedaria "colgada" EN_CURSO. Como las operaciones no deben quedar
-- sueltas, se deshace todo.
SELECT @id_partida_demo AS partida_creada,
       (SELECT COUNT(*) FROM partida_pregunta WHERE id_partida = @id_partida_demo) AS preguntas_cargadas,
       (SELECT cantidad_preguntas FROM modo_juego WHERE id = 2) AS preguntas_necesarias;

ROLLBACK;

-- Despues del ROLLBACK no quedo ni la partida ni sus preguntas.
-- (El AUTO_INCREMENT no vuelve atras: el proximo id saltea el numero usado.)
SELECT COUNT(*) AS partidas_despues FROM partida;
SELECT COUNT(*) AS preguntas_de_la_partida_demo
  FROM partida_pregunta WHERE id_partida = @id_partida_demo;

-- Version con COMMIT: la misma accion, con suficientes preguntas, usando el
-- procedimiento (Informatica tiene 27 activas, alcanza para un Clasico).
-- Deja una partida nueva EN_CURSO para el jugador 3.
CALL sp_iniciar_partida(3, 2, 1, @id_partida_ok);
SELECT * FROM v_resultado_partida WHERE id_partida = @id_partida_ok;

-- =============================================================================
-- 8. DIEZ CONSULTAS CON ENUNCIADO
-- =============================================================================

-- Consulta 1 (JOIN de 4 tablas + self-join de la reflexiva)
-- Enunciado: listar las preguntas activas con su categoria, la categoria
-- "madre" de esa categoria y la dificultad con sus puntos.
SELECT pr.id,
       pr.enunciado,
       c.nombre               AS categoria,
       COALESCE(cp.nombre, '-') AS categoria_padre,
       d.nombre               AS dificultad,
       d.puntos
  FROM pregunta pr
  JOIN categoria c       ON c.id  = pr.id_categoria
  LEFT JOIN categoria cp ON cp.id = c.id_categoria_padre
  JOIN dificultad d      ON d.id  = pr.id_dificultad
 WHERE pr.estado = 'ACTIVA'
 ORDER BY cp.nombre, c.nombre, d.nivel;

-- Consulta 2 (GROUP BY + HAVING, JOIN de 4 tablas)
-- Enunciado: jugadores con 2 o mas partidas finalizadas, con su cantidad de
-- partidas y su porcentaje de aciertos.
SELECT j.alias,
       COUNT(DISTINCT p.id)                     AS partidas_finalizadas,
       SUM(o.es_correcta)                       AS aciertos,
       COUNT(pp.id)                             AS respuestas,
       ROUND(100 * SUM(o.es_correcta) / COUNT(pp.id), 1) AS porcentaje_aciertos
  FROM jugador j
  JOIN partida p           ON p.id_jugador = j.id AND p.estado = 'FINALIZADA'
  JOIN partida_pregunta pp ON pp.id_partida = p.id
  JOIN opcion o            ON o.id = pp.id_opcion_elegida
 GROUP BY j.id, j.alias
HAVING COUNT(DISTINCT p.id) >= 2
 ORDER BY porcentaje_aciertos DESC;

-- Consulta 3 (ANTI-JOIN: LEFT JOIN ... IS NULL, 3 tablas)
-- Enunciado: preguntas activas que todavia no salieron en ninguna partida
-- (sirve para saber que contenido nunca se jugo).
SELECT pr.id, pr.enunciado, c.nombre AS categoria, d.nombre AS dificultad
  FROM pregunta pr
  JOIN categoria c  ON c.id = pr.id_categoria
  JOIN dificultad d ON d.id = pr.id_dificultad
  LEFT JOIN partida_pregunta pp ON pp.id_pregunta = pr.id
 WHERE pr.estado = 'ACTIVA'
   AND pp.id IS NULL
 ORDER BY c.nombre;

-- Consulta 4 (SUBCONSULTA ESCALAR en el WHERE)
-- Enunciado: partidas finalizadas cuyo puntaje supera el puntaje promedio de
-- todas las partidas finalizadas.
SELECT r.id_partida, r.alias, r.modo, r.categoria, r.puntaje,
       (SELECT ROUND(AVG(puntaje), 1)
          FROM v_resultado_partida WHERE estado = 'FINALIZADA') AS promedio_general
  FROM v_resultado_partida r
 WHERE r.estado = 'FINALIZADA'
   AND r.puntaje > (SELECT AVG(puntaje)
                      FROM v_resultado_partida WHERE estado = 'FINALIZADA')
 ORDER BY r.puntaje DESC;

-- Consulta 5 (GROUP BY + HAVING, JOIN de 4 tablas)
-- Enunciado: tasa de acierto de cada pregunta que se respondio al menos 3
-- veces, de la mas "dificil en la practica" a la mas facil.
SELECT pr.enunciado,
       d.nombre             AS dificultad_declarada,
       COUNT(pp.id)         AS veces_respondida,
       SUM(o.es_correcta)   AS aciertos,
       ROUND(100 * SUM(o.es_correcta) / COUNT(pp.id), 1) AS tasa_acierto
  FROM partida_pregunta pp
  JOIN pregunta pr  ON pr.id = pp.id_pregunta
  JOIN dificultad d ON d.id  = pr.id_dificultad
  JOIN opcion o     ON o.id  = pp.id_opcion_elegida
 GROUP BY pr.id, pr.enunciado, d.nombre
HAVING COUNT(pp.id) >= 3
 ORDER BY tasa_acierto ASC, veces_respondida DESC;

-- Consulta 6 (CONSULTA RECURSIVA sobre la reflexiva + JOIN de 3 tablas)
-- Enunciado: para cada categoria raiz, cuantas preguntas activas tiene en
-- total (contando todas sus subcategorias, en cualquier nivel) por dificultad.
WITH RECURSIVE descendencia (id_raiz, id_categoria) AS (
    SELECT id, id FROM categoria WHERE id_categoria_padre IS NULL
    UNION ALL
    SELECT de.id_raiz, c.id
      FROM categoria c
      JOIN descendencia de ON c.id_categoria_padre = de.id_categoria
)
SELECT raiz.nombre AS categoria_raiz,
       d.nombre    AS dificultad,
       COUNT(pr.id) AS preguntas_activas
  FROM descendencia de
  JOIN categoria raiz ON raiz.id = de.id_raiz
  JOIN pregunta pr    ON pr.id_categoria = de.id_categoria AND pr.estado = 'ACTIVA'
  JOIN dificultad d   ON d.id = pr.id_dificultad
 GROUP BY raiz.id, raiz.nombre, d.id, d.nombre
 ORDER BY raiz.nombre, d.id;

-- Consulta 7 (JOIN de 4 tablas con dos roles de OPCION)
-- Enunciado: detalle de la partida 1 (pantalla de revision): cada pregunta
-- en orden, la opcion que eligio el jugador y la opcion correcta.
SELECT pp.orden,
       pr.enunciado,
       elegida.texto  AS respondio,
       correcta.texto AS correcta,
       CASE WHEN elegida.es_correcta = 1 THEN 'BIEN' ELSE 'MAL' END AS resultado
  FROM partida_pregunta pp
  JOIN pregunta pr      ON pr.id = pp.id_pregunta
  JOIN opcion elegida   ON elegida.id = pp.id_opcion_elegida
  JOIN opcion correcta  ON correcta.id_pregunta = pr.id AND correcta.es_correcta = 1
 WHERE pp.id_partida = 1
 ORDER BY pp.orden;

-- Consulta 8 (SUBCONSULTA ESCALAR en el SELECT)
-- Enunciado: mejor puntaje de cada jugador y cuantos puntos le faltan para
-- alcanzar el record general del juego.
SELECT r.alias,
       MAX(r.puntaje) AS mejor_puntaje,
       (SELECT MAX(puntaje) FROM v_resultado_partida WHERE estado = 'FINALIZADA')
           - MAX(r.puntaje) AS distancia_al_record
  FROM v_resultado_partida r
 WHERE r.estado = 'FINALIZADA'
 GROUP BY r.id_jugador, r.alias
 ORDER BY mejor_puntaje DESC;

-- Consulta 9 (SUBCONSULTAS CORRELACIONADAS, regla R4)
-- Enunciado: preguntas en BORRADOR y por que todavia no se pueden activar
-- (cantidad de opciones y cantidad de opciones correctas).
SELECT pr.id,
       pr.enunciado,
       c.nombre AS categoria,
       (SELECT COUNT(*) FROM opcion o WHERE o.id_pregunta = pr.id) AS opciones,
       (SELECT COUNT(*) FROM opcion o
         WHERE o.id_pregunta = pr.id AND o.es_correcta = 1)        AS correctas
  FROM pregunta pr
  JOIN categoria c ON c.id = pr.id_categoria
 WHERE pr.estado = 'BORRADOR';

-- Consulta 10 (GROUP BY + HAVING, JOIN de 3 tablas)
-- Enunciado: "distractores" que mas enganan: opciones incorrectas que fueron
-- elegidas 2 o mas veces.
SELECT pr.enunciado,
       o.texto       AS opcion_incorrecta,
       COUNT(pp.id)  AS veces_elegida
  FROM opcion o
  JOIN partida_pregunta pp ON pp.id_opcion_elegida = o.id
  JOIN pregunta pr         ON pr.id = o.id_pregunta
 WHERE o.es_correcta = 0
 GROUP BY o.id, pr.enunciado, o.texto
HAVING COUNT(pp.id) >= 2
 ORDER BY veces_elegida DESC;

-- ==========================================
-- CATEGORIA: CULTURA GENERAL (aporte de Elias Aguero)
-- 10 preguntas random. Respetan la regla R4: cada pregunta se crea en
-- BORRADOR, se cargan sus opciones y recien despues se pasa a ACTIVA.
-- ==========================================

INSERT INTO categoria (nombre, descripcion, id_categoria_padre)
VALUES (
    'Cultura general',
    'Preguntas random, trampas y cultura general',
    NULL
)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);

SET @cat = LAST_INSERT_ID();

-- PREGUNTA 1
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Cuánto es 1 + 1?',
        'La respuesta es 2. ¡Una pregunta bastante complicada!',
        'BORRADOR', @cat, 3)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, '2', 1),
(@p, '11', 0),
(@p, '3', 0),
(@p, '0', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 2
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿De qué color era el caballo blanco de San Martín?',
        '¡Era blanco! La respuesta estaba en la misma pregunta.',
        'BORRADOR', @cat, 3)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, 'Blanco', 1),
(@p, 'Negro', 0),
(@p, 'Marrón', 0),
(@p, 'Gris', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 3
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Cuál es la capital de Australia?',
        'Canberra es la capital de Australia, no Sídney ni Melbourne.',
        'BORRADOR', @cat, 2)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, 'Sídney', 0),
(@p, 'Melbourne', 0),
(@p, 'Canberra', 1),
(@p, 'Perth', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 4
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Cuántos meses del año tienen al menos 28 días?',
        'Los 12 meses tienen al menos 28 días.',
        'BORRADOR', @cat, 3)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, '1', 0),
(@p, '2', 0),
(@p, '6', 0),
(@p, '12', 1)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 5
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Cuántos corazones tiene un pulpo?',
        'Los pulpos tienen tres corazones.',
        'BORRADOR', @cat, 2)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, 'Uno', 0),
(@p, 'Dos', 0),
(@p, 'Tres', 1),
(@p, 'Cuatro', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 6
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Cuántos lados tiene un hexágono?',
        'Un hexágono es un polígono de seis lados.',
        'BORRADOR', @cat, 1)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, 'Cinco', 0),
(@p, 'Seis', 1),
(@p, 'Siete', 0),
(@p, 'Ocho', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 7
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Cuál es el idioma oficial de Brasil?',
        'El idioma oficial de Brasil es el portugués.',
        'BORRADOR', @cat, 1)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, 'Español', 0),
(@p, 'Inglés', 0),
(@p, 'Portugués', 1),
(@p, 'Francés', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 8
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Qué planeta es conocido como el planeta rojo?',
        'Marte recibe ese nombre por el aspecto rojizo de su superficie.',
        'BORRADOR', @cat, 1)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, 'Venus', 0),
(@p, 'Marte', 1),
(@p, 'Júpiter', 0),
(@p, 'Saturno', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 9
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Cuántos días tiene un año bisiesto?',
        'Un año bisiesto tiene 366 días.',
        'BORRADOR', @cat, 2)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, '364', 0),
(@p, '365', 0),
(@p, '366', 1),
(@p, '367', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- PREGUNTA 10
INSERT INTO pregunta (enunciado, explicacion, estado, id_categoria, id_dificultad)
VALUES ('¿Qué color se obtiene al mezclar azul y amarillo?',
        'Al mezclar azul y amarillo se obtiene verde.',
        'BORRADOR', @cat, 1)
ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id);
SET @p = LAST_INSERT_ID();

INSERT INTO opcion (id_pregunta, texto, es_correcta) VALUES
(@p, 'Naranja', 0),
(@p, 'Violeta', 0),
(@p, 'Verde', 1),
(@p, 'Rojo', 0)
ON DUPLICATE KEY UPDATE es_correcta = VALUES(es_correcta);
UPDATE pregunta SET estado = 'ACTIVA' WHERE id = @p;

-- ==========================================
-- FIN DE CARGA
-- ==========================================


-- =============================================================================
-- FIN DEL SCRIPT. Para probar que las reglas rechazan datos invalidos, ver
-- sql/pruebas_reglas.sql (cada sentencia de ese archivo DEBE dar error).
-- =============================================================================
