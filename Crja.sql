INSERT INTO status (name, description) VALUES
    ('новая',      'Задача только что создана'),
    ('в работе',   'Исполнитель приступил'),
    ('на проверке','Ожидает проверки'),
    ('завершена',  'Выполнена и принята')
ON CONFLICT (name) DO NOTHING;

INSERT INTO employee (first_name, last_name, email, position) VALUES
    ('Иван',  'Петров',   'ivan@example.com',  'Руководитель проектов'),
    ('Мария', 'Сидорова', 'maria@example.com', 'Разработчик')
ON CONFLICT (email) DO NOTHING;

INSERT INTO project (name, manager_id)
SELECT 'Проект Демо', employee_id
FROM employee WHERE email = 'ivan@example.com';

INSERT INTO task (project_id, title, status_id, priority, created_by)
SELECT p.project_id, 'Задача A', s.status_id, 'medium', e.employee_id
FROM project p, status s, employee e
WHERE p.name = 'Проект Демо'
  AND s.name = 'новая'
  AND e.email = 'ivan@example.com';

INSERT INTO task (project_id, title, status_id, priority, created_by)
SELECT p.project_id, 'Задача B', s.status_id, 'medium', e.employee_id
FROM project p, status s, employee e
WHERE p.name = 'Проект Демо'
  AND s.name = 'новая'
  AND e.email = 'ivan@example.com';

-- ДЕМО 1. Нарушение CHECK (отрицательный размер файла)
DO $$
BEGIN
    INSERT INTO attachment (task_id, uploaded_by, file_name, file_path, file_size, mime_type)
    VALUES (
        (SELECT task_id FROM task WHERE title = 'Задача A' LIMIT 1),
        (SELECT employee_id FROM employee WHERE email = 'ivan@example.com'),
        'отчет.pdf',
        '/files/report_demo.pdf',
        -5,                     -- НЕДОПУСТИМО: размер меньше нуля
        'application/pdf'
    );
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Бизнес-ошибка: размер файла должен быть положительным числом (файл не может весить 0 байт или меньше). Текст СУБД: %', SQLERRM;
END;
$$;

-- ДЕМО 2. Нарушение FOREIGN KEY (зависимость от несуществующей задачи)
DO $$
BEGIN
    INSERT INTO task_dependency (task_id, depends_on_task_id, created_by)
    VALUES (
        (SELECT task_id FROM task WHERE title = 'Задача A' LIMIT 1),
        999999,                 -- НЕДОПУСТИМО: такой задачи нет
        NULL
    );
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Бизнес-ошибка: нельзя создать зависимость от несуществующей задачи — предшественник должен существовать. Текст СУБД: %', SQLERRM;
END;
$$;

-- ДЕМО 3. Нарушение UNIQUE (дублирующийся email сотрудника)
DO $$
BEGIN
    INSERT INTO employee (first_name, last_name, email, position)
    VALUES ('Другой', 'Петров', 'ivan@example.com', 'Аналитик');  -- email уже занят
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Бизнес-ошибка: сотрудник с таким email уже зарегистрирован, email должен быть уникальным. Текст СУБД: %', SQLERRM;
END;
$$;

-- ДЕМО 4. Нарушение NOT NULL (задача без названия)
DO $$
BEGIN
    INSERT INTO task (project_id, status_id, priority)  -- title намеренно не указан
    VALUES (
        (SELECT project_id FROM project WHERE name = 'Проект Демо' LIMIT 1),
        (SELECT status_id  FROM status  WHERE name = 'новая'      LIMIT 1),
        'high'
    );
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Бизнес-ошибка: задача должна иметь название — поле title обязательно. Текст СУБД: %', SQLERRM;
END;
$$;

-- ДЕМО 5. Триггерное ограничение (циклическая зависимость задач)
DO $$
DECLARE
    v_a INT := (SELECT task_id FROM task WHERE title = 'Задача A' ORDER BY task_id LIMIT 1);
    v_b INT := (SELECT task_id FROM task WHERE title = 'Задача B' ORDER BY task_id LIMIT 1);
BEGIN
    -- Сначала создаём корректную зависимость: «A зависит от B»
    INSERT INTO task_dependency (task_id, depends_on_task_id)
    VALUES (v_a, v_b)
    ON CONFLICT DO NOTHING;

    -- Теперь пытаемся создать обратную: «B зависит от A» -> цикл A <-> B
    INSERT INTO task_dependency (task_id, depends_on_task_id)
    VALUES (v_b, v_a);
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Бизнес-ошибка: нельзя создать циклическую зависимость (A зависит от B, а B от A) — работа зайдёт в тупик. Текст СУБД: %', SQLERRM;
END;
$$;