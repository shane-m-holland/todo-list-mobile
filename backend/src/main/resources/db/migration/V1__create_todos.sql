CREATE TABLE todos (
    id         uuid         PRIMARY KEY,
    -- Insertion order. Breaks ties between todos created within the same millisecond.
    seq        bigint       GENERATED ALWAYS AS IDENTITY UNIQUE,
    title      varchar(200) NOT NULL,
    notes      varchar(2000),
    completed  boolean      NOT NULL DEFAULT false,
    created_at timestamptz  NOT NULL,
    updated_at timestamptz  NOT NULL,
    -- Mirror the contract's constraints so a bug in the service can't store invalid data.
    CONSTRAINT todos_title_not_blank CHECK (title ~ '\S'),
    CONSTRAINT todos_notes_not_empty CHECK (notes IS NULL OR notes <> '')
);

CREATE INDEX todos_created_idx ON todos (created_at, seq);
