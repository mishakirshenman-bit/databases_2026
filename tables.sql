-- Таблица 1: Зависимости задач (M:N «задача ↔ задача»)
CREATE TABLE task_dependency (
    depends_on_task_id INT NOT NULL,
    task_id            INT NOT NULL,
    dependency_type    VARCHAR(50) NOT NULL DEFAULT 'finish_to_start'
        CHECK (dependency_type IN ('finish_to_start','start_to_start',
                                   'finish_to_finish','start_to_finish')),
    created_by         INT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_task_dependency
        PRIMARY KEY (task_id, depends_on_task_id),

    CONSTRAINT fk_dependency_task
        FOREIGN KEY (task_id) REFERENCES task(task_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_dependency_depends_on
        FOREIGN KEY (depends_on_task_id) REFERENCES task(task_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_dependency_created_by
        FOREIGN KEY (created_by) REFERENCES employee(employee_id)
        ON DELETE SET NULL,

    -- бизнес-правило: задача не может зависеть от самой себя
    CONSTRAINT chk_no_self_dependency
        CHECK (task_id <> depends_on_task_id)
);

-- Индекс для обратного обхода: «какие задачи зависят от этой задачи?»
-- (частый запрос «показать блокируемые задачей работы»)
CREATE INDEX idx_dependency_depends_on
    ON task_dependency (depends_on_task_id);

-- Таблица 2: Вложения к задачам (опционально — к комментарию)
CREATE TABLE attachment (
    attachment_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    task_id       INT NOT NULL,
    comment_id    INT,
    uploaded_by   INT,
    file_name     VARCHAR(255) NOT NULL,
    file_path     TEXT NOT NULL,
    file_size     BIGINT NOT NULL,
    mime_type     VARCHAR(100),
    uploaded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_attachment_task
        FOREIGN KEY (task_id) REFERENCES task(task_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_attachment_uploaded_by
        FOREIGN KEY (uploaded_by) REFERENCES employee(employee_id)
        ON DELETE SET NULL,

    -- составной FK: если вложение привязано к комментарию,
    -- этот комментарий обязан принадлежать той же задаче
    CONSTRAINT fk_attachment_comment_task
        FOREIGN KEY (comment_id, task_id)
        REFERENCES comment(comment_id, task_id)
        ON DELETE CASCADE,

    -- бизнес-правила
    CONSTRAINT chk_attachment_size CHECK (file_size > 0),
    CONSTRAINT chk_attachment_name CHECK (btrim(file_name) <> '')
);

-- Для составного FK нужно уникальное ограничение на (comment_id, task_id)
ALTER TABLE comment
    ADD CONSTRAINT uq_comment_id_task UNIQUE (comment_id, task_id);

-- Уникальность пути к файлу (нельзя дважды хранить один файл)
CREATE UNIQUE INDEX uq_attachment_file_path ON attachment (file_path);

-- Индексы для частых запросов («вложения задачи», «вложения комментария»)
CREATE INDEX idx_attachment_task    ON attachment (task_id);
CREATE INDEX idx_attachment_comment ON attachment (comment_id);

-- Триггерное ограничение: запрет циклических зависимостей задач
-- (A зависит от B  И  B зависит от A — недопустимо)
CREATE OR REPLACE FUNCTION fn_prevent_circular_dependency()
RETURNS TRIGGER AS $$
BEGIN
    -- Проверяем: существует ли уже путь (по направлению «предшественник → зависимый»)
    -- от NEW.task_id к NEW.depends_on_task_id. Если да — добавление новой связи
    -- замкнёт цикл.
    IF EXISTS (
        WITH RECURSIVE chain AS (
            SELECT td.task_id AS node
            FROM task_dependency td
            WHERE td.depends_on_task_id = NEW.task_id
            UNION
            SELECT td.task_id
            FROM task_dependency td
            JOIN chain c ON td.depends_on_task_id = c.node
        )
        SELECT 1 FROM chain WHERE node = NEW.depends_on_task_id
    ) THEN
        RAISE EXCEPTION 'circular task dependency detected';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_task_dependency_no_cycle
BEFORE INSERT OR UPDATE OF task_id, depends_on_task_id ON task_dependency
FOR EACH ROW EXECUTE FUNCTION fn_prevent_circular_dependency();

-- Дополнительные бизнес-ограничения для существующих таблиц
-- История статуса: переход «с того же на тот же» бессмыслен
ALTER TABLE task_status_history
    ADD CONSTRAINT chk_status_change
    CHECK (from_status_id IS DISTINCT FROM to_status_id);

-- Доп. индекс под частый запрос №2 из ДЗ №1
-- («просроченные задачи»: фильтр по статусу + сроку)
CREATE INDEX idx_task_status_deadline ON task (status_id, deadline);