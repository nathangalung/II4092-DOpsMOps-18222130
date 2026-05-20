-- ============================================================================
-- Crypto Use Case — PostgreSQL Extensions
-- ============================================================================
-- Extends the generic pipeline schema with crypto-specific fields.
-- Run AFTER platform/services/base/database/init_postgres.sql.
-- ============================================================================

-- Add crypto-specific columns to predictions (if not already present)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'pipeline' AND table_name = 'predictions'
        AND column_name = 'predicted_volatility'
    ) THEN
        ALTER TABLE pipeline.predictions
            ADD COLUMN predicted_volatility DOUBLE PRECISION,
            ADD COLUMN model_type VARCHAR(50);
    END IF;
END
$$;
