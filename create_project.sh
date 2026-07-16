#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}📊 Data Engineering Project Setup${NC}"
echo "===================================="

# Get project name from user
echo -e "${YELLOW}Enter project name:${NC}"
read PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}❌ Project name cannot be empty${NC}"
    exit 1
fi

# Create main project directory
echo -e "${BLUE}📁 Creating project structure...${NC}"
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Create folder structure
mkdir -p config
mkdir -p logs
mkdir -p src/database
mkdir -p src/logging
mkdir -p src/extract
mkdir -p src/transform
mkdir -p src/load
mkdir -p src/quality
mkdir -p src/utils
mkdir -p data/raw
mkdir -p data/processed
mkdir -p data/archive
mkdir -p tests

# Create config files
cat > config/config.yaml << 'EOF'
# Application Configuration
app:
  name: ${PROJECT_NAME}
  version: 1.0.0
  environment: development  # development, staging, production

# Logging Configuration
logging:
  level: INFO
  format: "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
  handlers:
    - console
    - file
  file_config:
    path: logs/app.log
    max_bytes: 10485760  # 10MB
    backup_count: 5

# Pipeline Configuration
pipeline:
  batch_size: 10000
  retry_attempts: 3
  timeout_seconds: 300
EOF

cat > config/database.yaml << 'EOF'
# Database Configuration
database:
  # PostgreSQL example
  postgresql:
    host: localhost
    port: 5432
    database: ${DB_NAME}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    pool_size: 10
    max_overflow: 20
    
  # MySQL example
  mysql:
    host: localhost
    port: 3306
    database: ${DB_NAME}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    
  # SQLite example
  sqlite:
    database: data/processed/etl.db
EOF

# Create Python source files with content
cat > src/database/connection.py << 'EOF'
"""Database connection management."""
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import logging

logger = logging.getLogger(__name__)

class DatabaseConnection:
    """Manages database connections."""
    
    def __init__(self, connection_string: str):
        self.connection_string = connection_string
        self.engine = None
        self.Session = None
        
    def connect(self):
        """Establish database connection."""
        try:
            self.engine = create_engine(
                self.connection_string,
                pool_pre_ping=True,
                pool_recycle=3600
            )
            self.Session = sessionmaker(bind=self.engine)
            logger.info("Database connection established successfully")
            return self.engine
        except Exception as e:
            logger.error(f"Failed to connect to database: {e}")
            raise
            
    def get_session(self):
        """Get a new database session."""
        if not self.Session:
            self.connect()
        return self.Session()
        
    def close(self):
        """Close database connection."""
        if self.engine:
            self.engine.dispose()
            logger.info("Database connection closed")
EOF

cat > src/database/engine.py << 'EOF'
"""Database engine configuration."""
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
import yaml
import os

Base = declarative_base()

class DatabaseEngine:
    """Database engine factory."""
    
    def __init__(self, config_path: str = "config/database.yaml"):
        self.config_path = config_path
        self.config = self._load_config()
        
    def _load_config(self):
        """Load database configuration from YAML."""
        with open(self.config_path, 'r') as f:
            return yaml.safe_load(f)
            
    def get_postgres_engine(self):
        """Create PostgreSQL engine."""
        config = self.config['database']['postgresql']
        connection_string = (
            f"postgresql://{config['username']}:{config['password']}"
            f"@{config['host']}:{config['port']}/{config['database']}"
        )
        return create_engine(
            connection_string,
            pool_size=config.get('pool_size', 10),
            max_overflow=config.get('max_overflow', 20)
        )
        
    def get_sqlite_engine(self):
        """Create SQLite engine."""
        config = self.config['database']['sqlite']
        return create_engine(f"sqlite:///{config['database']}")
EOF

cat > src/database/session.py << 'EOF'
"""Database session management."""
from contextlib import contextmanager
from src.database.engine import DatabaseEngine
import logging

logger = logging.getLogger(__name__)

class SessionManager:
    """Manages database sessions."""
    
    def __init__(self, engine):
        self.engine = engine
        
    @contextmanager
    def get_session(self):
        """Context manager for database sessions."""
        from sqlalchemy.orm import sessionmaker
        Session = sessionmaker(bind=self.engine)
        session = Session()
        try:
            yield session
            session.commit()
        except Exception as e:
            session.rollback()
            logger.error(f"Session error: {e}")
            raise
        finally:
            session.close()
EOF

cat > src/database/models.py << 'EOF'
"""SQLAlchemy ORM models."""
from sqlalchemy import Column, Integer, String, DateTime, Float, Boolean
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime

Base = declarative_base()

class DataRecord(Base):
    """Example data record model."""
    __tablename__ = 'data_records'
    
    id = Column(Integer, primary_key=True)
    record_id = Column(String(50), unique=True, nullable=False)
    name = Column(String(100))
    value = Column(Float)
    category = Column(String(50))
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    is_active = Column(Boolean, default=True)
    
    def __repr__(self):
        return f"<DataRecord(id={self.id}, name={self.name})>"
EOF

cat > src/logging/logger.py << 'EOF'
"""Centralized logging configuration."""
import logging
import logging.config
import yaml
import os
from datetime import datetime

class Logger:
    """Custom logger configuration."""
    
    def __init__(self, config_path: str = "config/config.yaml"):
        self.config_path = config_path
        self.logger = None
        
    def setup(self):
        """Setup logging configuration."""
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)
                
            log_config = config.get('logging', {})
            
            # Create logs directory if it doesn't exist
            log_path = log_config.get('file_config', {}).get('path', 'logs/app.log')
            os.makedirs(os.path.dirname(log_path), exist_ok=True)
            
            # Basic logging configuration
            logging.basicConfig(
                level=getattr(logging, log_config.get('level', 'INFO')),
                format=log_config.get('format', '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
            )
            
            # Add file handler if configured
            if 'file' in log_config.get('handlers', []):
                file_handler = logging.FileHandler(log_path)
                file_handler.setFormatter(logging.Formatter(log_config['format']))
                logging.getLogger().addHandler(file_handler)
                
            self.logger = logging.getLogger(__name__)
            self.logger.info("Logging configured successfully")
            
        except Exception as e:
            print(f"Failed to setup logging: {e}")
            raise
            
    def get_logger(self, name: str = None):
        """Get a logger instance."""
        if not self.logger:
            self.setup()
        return logging.getLogger(name or __name__)
EOF

cat > src/logging/custom_formatter.py << 'EOF'
"""Custom log formatters."""
import logging
from datetime import datetime
import json

class JSONFormatter(logging.Formatter):
    """JSON log formatter."""
    
    def format(self, record):
        log_data = {
            'timestamp': datetime.utcnow().isoformat(),
            'level': record.levelname,
            'module': record.name,
            'message': record.getMessage(),
            'filename': record.filename,
            'lineno': record.lineno
        }
        
        if hasattr(record, 'extra'):
            log_data.update(record.extra)
            
        return json.dumps(log_data)

class ColoredFormatter(logging.Formatter):
    """Color-coded console formatter."""
    
    COLORS = {
        'DEBUG': '\033[36m',    # Cyan
        'INFO': '\033[32m',     # Green
        'WARNING': '\033[33m',  # Yellow
        'ERROR': '\033[31m',    # Red
        'CRITICAL': '\033[35m'  # Magenta
    }
    RESET = '\033[0m'
    
    def format(self, record):
        color = self.COLORS.get(record.levelname, self.RESET)
        record.levelname = f"{color}{record.levelname}{self.RESET}"
        return super().format(record)
EOF

# Create extractor files
cat > src/extract/csv_reader.py << 'EOF'
"""CSV data extraction."""
import pandas as pd
import logging
from typing import Optional
from pathlib import Path

logger = logging.getLogger(__name__)

class CSVReader:
    """CSV file reader for data extraction."""
    
    def __init__(self, file_path: str):
        self.file_path = Path(file_path)
        
    def read(self, **kwargs) -> pd.DataFrame:
        """Read CSV file into DataFrame."""
        try:
            if not self.file_path.exists():
                raise FileNotFoundError(f"File not found: {self.file_path}")
                
            df = pd.read_csv(self.file_path, **kwargs)
            logger.info(f"Successfully read {len(df)} rows from {self.file_path}")
            return df
            
        except Exception as e:
            logger.error(f"Failed to read CSV file: {e}")
            raise
            
    def read_chunks(self, chunk_size: int = 10000, **kwargs):
        """Read CSV file in chunks."""
        try:
            for chunk in pd.read_csv(self.file_path, chunksize=chunk_size, **kwargs):
                yield chunk
                logger.debug(f"Read chunk of {len(chunk)} rows")
        except Exception as e:
            logger.error(f"Failed to read CSV in chunks: {e}")
            raise
EOF

cat > src/extract/json_reader.py << 'EOF'
"""JSON data extraction."""
import json
import pandas as pd
import logging
from pathlib import Path
from typing import Any, Dict, List

logger = logging.getLogger(__name__)

class JSONReader:
    """JSON file reader for data extraction."""
    
    def __init__(self, file_path: str):
        self.file_path = Path(file_path)
        
    def read(self) -> List[Dict[str, Any]]:
        """Read JSON file."""
        try:
            if not self.file_path.exists():
                raise FileNotFoundError(f"File not found: {self.file_path}")
                
            with open(self.file_path, 'r') as f:
                data = json.load(f)
                
            logger.info(f"Successfully read JSON from {self.file_path}")
            return data
            
        except Exception as e:
            logger.error(f"Failed to read JSON file: {e}")
            raise
            
    def to_dataframe(self) -> pd.DataFrame:
        """Read JSON file as DataFrame."""
        data = self.read()
        df = pd.DataFrame(data)
        logger.info(f"Converted JSON to DataFrame with {len(df)} rows")
        return df
EOF

cat > src/extract/sql_reader.py << 'EOF'
"""SQL data extraction."""
import pandas as pd
import logging
from sqlalchemy import text
from src.database.connection import DatabaseConnection

logger = logging.getLogger(__name__)

class SQLReader:
    """SQL data extractor."""
    
    def __init__(self, connection: DatabaseConnection):
        self.connection = connection
        
    def read_query(self, query: str, params: dict = None) -> pd.DataFrame:
        """Execute SQL query and return results as DataFrame."""
        try:
            with self.connection.get_session() as session:
                result = pd.read_sql(query, session.bind, params=params)
                logger.info(f"Query returned {len(result)} rows")
                return result
                
        except Exception as e:
            logger.error(f"Failed to execute query: {e}")
            raise
            
    def read_table(self, table_name: str, limit: int = None) -> pd.DataFrame:
        """Read entire table."""
        query = f"SELECT * FROM {table_name}"
        if limit:
            query += f" LIMIT {limit}"
        return self.read_query(query)
EOF

# Create transformer files
cat > src/transform/cleaning.py << 'EOF'
"""Data cleaning operations."""
import pandas as pd
import logging
from typing import Optional

logger = logging.getLogger(__name__)

class DataCleaner:
    """Data cleaning pipeline."""
    
    def __init__(self, df: pd.DataFrame):
        self.df = df.copy()
        
    def remove_duplicates(self, subset: Optional[list] = None) -> pd.DataFrame:
        """Remove duplicate rows."""
        initial_len = len(self.df)
        self.df = self.df.drop_duplicates(subset=subset)
        removed = initial_len - len(self.df)
        logger.info(f"Removed {removed} duplicate rows")
        return self.df
        
    def handle_missing(self, strategy: str = 'drop', fill_value=None) -> pd.DataFrame:
        """Handle missing values."""
        if strategy == 'drop':
            initial_len = len(self.df)
            self.df = self.df.dropna()
            removed = initial_len - len(self.df)
            logger.info(f"Dropped {removed} rows with missing values")
        elif strategy == 'fill':
            self.df = self.df.fillna(fill_value)
            logger.info(f"Filled missing values with {fill_value}")
        elif strategy == 'interpolate':
            self.df = self.df.interpolate()
            logger.info("Interpolated missing values")
        return self.df
        
    def remove_outliers(self, column: str, method: str = 'iqr') -> pd.DataFrame:
        """Remove outliers from numeric columns."""
        if method == 'iqr':
            Q1 = self.df[column].quantile(0.25)
            Q3 = self.df[column].quantile(0.75)
            IQR = Q3 - Q1
            lower_bound = Q1 - 1.5 * IQR
            upper_bound = Q3 + 1.5 * IQR
            self.df = self.df[(self.df[column] >= lower_bound) & 
                              (self.df[column] <= upper_bound)]
            logger.info(f"Removed outliers from column '{column}' using IQR method")
        return self.df
        
    def clean(self) -> pd.DataFrame:
        """Run full cleaning pipeline."""
        self.remove_duplicates()
        self.handle_missing(strategy='drop')
        return self.df
EOF

cat > src/transform/validation.py << 'EOF'
"""Data validation operations."""
import pandas as pd
import logging
from typing import Dict, Any, List
from cerberus import Validator

logger = logging.getLogger(__name__)

class DataValidator:
    """Data validation framework."""
    
    def __init__(self, schema: Dict[str, Any]):
        self.schema = schema
        self.validator = Validator(schema)
        self.errors = []
        
    def validate_row(self, row: Dict[str, Any]) -> bool:
        """Validate a single row."""
        if self.validator.validate(row):
            return True
        else:
            self.errors.append(self.validator.errors)
            return False
            
    def validate_dataframe(self, df: pd.DataFrame) -> tuple:
        """Validate all rows in DataFrame."""
        valid_rows = []
        invalid_rows = []
        self.errors = []
        
        for idx, row in df.iterrows():
            if self.validate_row(row.to_dict()):
                valid_rows.append(row)
            else:
                invalid_rows.append(row)
                
        logger.info(f"Validation complete: {len(valid_rows)} valid, {len(invalid_rows)} invalid")
        
        if invalid_rows:
            logger.warning(f"Found {len(invalid_rows)} invalid rows")
            
        return pd.DataFrame(valid_rows), pd.DataFrame(invalid_rows)
        
    def check_schema(self, df: pd.DataFrame) -> bool:
        """Check if DataFrame matches expected schema."""
        expected_columns = set(self.schema.keys())
        actual_columns = set(df.columns)
        
        missing = expected_columns - actual_columns
        extra = actual_columns - expected_columns
        
        if missing:
            logger.error(f"Missing columns: {missing}")
        if extra:
            logger.warning(f"Extra columns: {extra}")
            
        return len(missing) == 0
EOF

cat > src/transform/business_rules.py << 'EOF'
"""Business rules and transformations."""
import pandas as pd
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

class BusinessRules:
    """Business rule engine."""
    
    def __init__(self, df: pd.DataFrame):
        self.df = df.copy()
        self.transformations = []
        
    def add_rule(self, name: str, rule_fn):
        """Add a business rule."""
        self.transformations.append({
            'name': name,
            'function': rule_fn
        })
        logger.info(f"Added business rule: {name}")
        
    def apply_currency_conversion(self, amount_col: str, rate: float, target_col: str) -> pd.DataFrame:
        """Apply currency conversion rule."""
        self.df[target_col] = self.df[amount_col] * rate
        logger.info(f"Applied currency conversion: {amount_col} -> {target_col}")
        return self.df
        
    def calculate_derived_fields(self) -> pd.DataFrame:
        """Calculate common derived fields."""
        # Example: Calculate age from birth date
        if 'birth_date' in self.df.columns:
            self.df['age'] = (pd.Timestamp.now() - pd.to_datetime(self.df['birth_date'])).dt.days // 365
            logger.info("Calculated age from birth_date")
            
        # Example: Categorize values
        if 'value' in self.df.columns:
            self.df['value_category'] = pd.cut(
                self.df['value'],
                bins=[0, 100, 1000, 10000, float('inf')],
                labels=['small', 'medium', 'large', 'very_large']
            )
            logger.info("Categorized values")
            
        return self.df
        
    def apply_all(self) -> pd.DataFrame:
        """Apply all registered business rules."""
        for rule in self.transformations:
            self.df = rule['function'](self.df)
            logger.info(f"Applied rule: {rule['name']}")
        return self.df
EOF

# Create loader files
cat > src/load/sql_loader.py << 'EOF'
"""SQL data loader."""
import pandas as pd
import logging
from sqlalchemy import text
from src.database.connection import DatabaseConnection

logger = logging.getLogger(__name__)

class SQLLoader:
    """SQL data loader for single rows."""
    
    def __init__(self, connection: DatabaseConnection):
        self.connection = connection
        
    def insert_row(self, table_name: str, data: dict) -> bool:
        """Insert a single row."""
        try:
            columns = ', '.join(data.keys())
            placeholders = ', '.join([f':{key}' for key in data.keys()])
            query = f"INSERT INTO {table_name} ({columns}) VALUES ({placeholders})"
            
            with self.connection.get_session() as session:
                session.execute(text(query), data)
                logger.info(f"Inserted row into {table_name}")
                return True
                
        except Exception as e:
            logger.error(f"Failed to insert row: {e}")
            return False
            
    def insert_many(self, table_name: str, data: list) -> int:
        """Insert multiple rows."""
        try:
            if not data:
                return 0
                
            columns = ', '.join(data[0].keys())
            placeholders = ', '.join([f':{key}' for key in data[0].keys()])
            query = f"INSERT INTO {table_name} ({columns}) VALUES ({placeholders})"
            
            with self.connection.get_session() as session:
                for row in data:
                    session.execute(text(query), row)
                session.commit()
                logger.info(f"Inserted {len(data)} rows into {table_name}")
                return len(data)
                
        except Exception as e:
            logger.error(f"Failed to insert rows: {e}")
            return 0
EOF

cat > src/load/bulk_loader.py << 'EOF'
"""Bulk data loader."""
import pandas as pd
import logging
from sqlalchemy import text
from src.database.connection import DatabaseConnection

logger = logging.getLogger(__name__)

class BulkLoader:
    """Efficient bulk data loading."""
    
    def __init__(self, connection: DatabaseConnection):
        self.connection = connection
        
    def load_dataframe(self, df: pd.DataFrame, table_name: str, 
                       if_exists: str = 'append', chunk_size: int = 10000) -> int:
        """Load DataFrame into database table."""
        try:
            with self.connection.get_session() as session:
                rows_inserted = 0
                for start in range(0, len(df), chunk_size):
                    chunk = df.iloc[start:start + chunk_size]
                    chunk.to_sql(
                        table_name,
                        session.bind,
                        if_exists=if_exists if start == 0 else 'append',
                        index=False
                    )
                    rows_inserted += len(chunk)
                    logger.info(f"Loaded chunk: {len(chunk)} rows")
                    
                logger.info(f"Successfully loaded {rows_inserted} rows into {table_name}")
                return rows_inserted
                
        except Exception as e:
            logger.error(f"Failed to load data: {e}")
            raise
            
    def load_csv_to_table(self, csv_path: str, table_name: str, 
                         chunk_size: int = 10000, **kwargs) -> int:
        """Load CSV directly to database."""
        try:
            total_rows = 0
            for chunk in pd.read_csv(csv_path, chunksize=chunk_size, **kwargs):
                total_rows += self.load_dataframe(chunk, table_name, 
                                                if_exists='append' if total_rows > 0 else 'replace')
            logger.info(f"Loaded {total_rows} rows from {csv_path} to {table_name}")
            return total_rows
            
        except Exception as e:
            logger.error(f"Failed to load CSV to table: {e}")
            raise
EOF

# Create quality check files
cat > src/quality/null_checks.py << 'EOF'
"""Null value checks for data quality."""
import pandas as pd
import logging
from typing import Dict, List

logger = logging.getLogger(__name__)

class NullChecker:
    """Check for null/missing values."""
    
    def __init__(self, df: pd.DataFrame):
        self.df = df
        
    def get_null_counts(self) -> Dict[str, int]:
        """Get null counts per column."""
        null_counts = self.df.isnull().sum().to_dict()
        logger.info(f"Null value counts: {null_counts}")
        return null_counts
        
    def get_null_percentages(self) -> Dict[str, float]:
        """Get null percentages per column."""
        total_rows = len(self.df)
        percentages = {col: (count / total_rows * 100) 
                      for col, count in self.get_null_counts().items()}
        return percentages
        
    def check_null_threshold(self, threshold: float = 0.1) -> Dict[str, bool]:
        """Check if any column exceeds null threshold."""
        percentages = self.get_null_percentages()
        results = {col: pct <= threshold * 100 for col, pct in percentages.items()}
        
        failing = [col for col, passed in results.items() if not passed]
        if failing:
            logger.warning(f"Columns exceeding {threshold*100}% null threshold: {failing}")
        
        return results
        
    def get_rows_with_nulls(self, subset: List[str] = None) -> pd.DataFrame:
        """Get rows that contain null values."""
        if subset:
            null_rows = self.df[self.df[subset].isnull().any(axis=1)]
        else:
            null_rows = self.df[self.df.isnull().any(axis=1)]
            
        logger.info(f"Found {len(null_rows)} rows with null values")
        return null_rows
EOF

cat > src/quality/duplicate_checks.py << 'EOF'
"""Duplicate detection for data quality."""
import pandas as pd
import logging
from typing import List, Dict

logger = logging.getLogger(__name__)

class DuplicateChecker:
    """Check for duplicate records."""
    
    def __init__(self, df: pd.DataFrame):
        self.df = df
        
    def get_duplicates(self, subset: List[str] = None) -> pd.DataFrame:
        """Get duplicate rows."""
        duplicates = self.df.duplicated(subset=subset, keep=False)
        duplicate_rows = self.df[duplicates]
        
        if subset:
            logger.info(f"Found {len(duplicate_rows)} duplicate rows based on {subset}")
        else:
            logger.info(f"Found {len(duplicate_rows)} duplicate rows")
            
        return duplicate_rows
        
    def get_duplicate_counts(self, subset: List[str] = None) -> pd.Series:
        """Count duplicates per group."""
        if subset:
            duplicate_counts = self.df.groupby(subset).size()
            duplicates = duplicate_counts[duplicate_counts > 1]
        else:
            duplicate_counts = self.df.groupby(list(self.df.columns)).size()
            duplicates = duplicate_counts[duplicate_counts > 1]
            
        logger.info(f"Found {len(duplicates)} duplicate groups")
        return duplicates
        
    def get_duplicate_summary(self) -> Dict:
        """Get duplicate summary statistics."""
        total_rows = len(self.df)
        duplicate_rows = len(self.get_duplicates())
        
        summary = {
            'total_rows': total_rows,
            'duplicate_rows': duplicate_rows,
            'duplicate_percentage': (duplicate_rows / total_rows) * 100 if total_rows > 0 else 0,
            'unique_rows': total_rows - duplicate_rows
        }
        
        logger.info(f"Duplicate summary: {summary}")
        return summary
EOF

cat > src/quality/schema_checks.py << 'EOF'
"""Schema validation for data quality."""
import pandas as pd
import logging
from typing import Dict, List, Any

logger = logging.getLogger(__name__)

class SchemaChecker:
    """Check data schema and types."""
    
    def __init__(self, df: pd.DataFrame):
        self.df = df
        self.expected_schema = {}
        
    def set_expected_schema(self, schema: Dict[str, str]):
        """Set expected column types."""
        self.expected_schema = schema
        logger.info(f"Set expected schema with {len(schema)} columns")
        
    def get_actual_schema(self) -> Dict[str, str]:
        """Get actual column types."""
        actual = {col: str(dtype) for col, dtype in self.df.dtypes.items()}
        return actual
        
    def check_schema_mismatch(self) -> Dict[str, List[str]]:
        """Check for schema mismatches."""
        actual = self.get_actual_schema()
        mismatches = {
            'missing_columns': [],
            'extra_columns': [],
            'type_mismatches': []
        }
        
        # Check missing and extra columns
        expected_cols = set(self.expected_schema.keys())
        actual_cols = set(actual.keys())
        
        mismatches['missing_columns'] = list(expected_cols - actual_cols)
        mismatches['extra_columns'] = list(actual_cols - expected_cols)
        
        # Check type mismatches
        for col in expected_cols.intersection(actual_cols):
            if self.expected_schema[col] != actual[col]:
                mismatches['type_mismatches'].append(
                    f"{col}: expected {self.expected_schema[col]}, got {actual[col]}"
                )
                
        if any(mismatches.values()):
            logger.warning(f"Schema mismatches found: {mismatches}")
        else:
            logger.info("Schema validation passed")
            
        return mismatches
        
    def validate_schema(self) -> bool:
        """Validate entire schema."""
        mismatches = self.check_schema_mismatch()
        return all(len(v) == 0 for v in mismatches.values())
EOF

# Create utils files
cat > src/utils/helpers.py << 'EOF'
"""Shared utility functions."""
import hashlib
import json
from typing import Any, Dict
import logging

logger = logging.getLogger(__name__)

def generate_hash(data: Any) -> str:
    """Generate SHA-256 hash for any data."""
    json_str = json.dumps(data, sort_keys=True)
    return hashlib.sha256(json_str.encode()).hexdigest()

def chunk_list(lst: list, chunk_size: int):
    """Split list into chunks."""
    for i in range(0, len(lst), chunk_size):
        yield lst[i:i + chunk_size]

def flatten_dict(nested: Dict[str, Any], parent_key: str = '', sep: str = '.') -> Dict:
    """Flatten nested dictionary."""
    items = {}
    for key, value in nested.items():
        new_key = f"{parent_key}{sep}{key}" if parent_key else key
        if isinstance(value, dict):
            items.update(flatten_dict(value, new_key, sep=sep))
        else:
            items[new_key] = value
    return items

def safe_json_loads(json_str: str, default: Any = None) -> Any:
    """Safely load JSON string."""
    try:
        return json.loads(json_str)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON: {e}")
        return default
EOF

cat > src/utils/file_utils.py << 'EOF'
"""File utility functions."""
import os
import shutil
from pathlib import Path
import logging
from typing import List, Optional

logger = logging.getLogger(__name__)

def ensure_directory(path: str) -> Path:
    """Ensure directory exists."""
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True)
    return path

def list_files(directory: str, pattern: str = "*") -> List[Path]:
    """List files in directory matching pattern."""
    path = Path(directory)
    return list(path.glob(pattern))

def move_file(src: str, dest: str) -> bool:
    """Move file from source to destination."""
    try:
        shutil.move(src, dest)
        logger.info(f"Moved {src} to {dest}")
        return True
    except Exception as e:
        logger.error(f"Failed to move file: {e}")
        return False

def copy_file(src: str, dest: str) -> bool:
    """Copy file from source to destination."""
    try:
        shutil.copy2(src, dest)
        logger.info(f"Copied {src} to {dest}")
        return True
    except Exception as e:
        logger.error(f"Failed to copy file: {e}")
        return False

def get_file_size(file_path: str) -> int:
    """Get file size in bytes."""
    return os.path.getsize(file_path)

def cleanup_old_files(directory: str, max_age_days: int = 30):
    """Delete files older than max_age_days."""
    import time
    now = time.time()
    threshold = now - (max_age_days * 86400)
    
    for file_path in Path(directory).iterdir():
        if file_path.is_file() and file_path.stat().st_mtime < threshold:
            file_path.unlink()
            logger.info(f"Deleted old file: {file_path}")
EOF

cat > src/utils/date_utils.py << 'EOF'
"""Date and time utility functions."""
from datetime import datetime, timedelta
import logging
from typing import Optional, Union

logger = logging.getLogger(__name__)

def parse_date(date_str: str, formats: list = None) -> Optional[datetime]:
    """Parse date string using multiple formats."""
    if formats is None:
        formats = [
            '%Y-%m-%d',
            '%Y-%m-%d %H:%M:%S',
            '%d-%m-%Y',
            '%m/%d/%Y',
            '%Y%m%d'
        ]
        
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
            
    logger.warning(f"Could not parse date: {date_str}")
    return None

def get_date_range(start_date: Union[str, datetime], 
                  end_date: Union[str, datetime]) -> list:
    """Generate list of dates between start and end."""
    if isinstance(start_date, str):
        start_date = parse_date(start_date)
    if isinstance(end_date, str):
        end_date = parse_date(end_date)
        
    dates = []
    current = start_date
    while current <= end_date:
        dates.append(current)
        current += timedelta(days=1)
        
    return dates

def format_date(date: datetime, fmt: str = '%Y-%m-%d') -> str:
    """Format datetime object."""
    return date.strftime(fmt)

def get_current_timestamp() -> str:
    """Get current timestamp as string."""
    return datetime.now().isoformat()

def days_between(date1: Union[str, datetime], 
                 date2: Union[str, datetime]) -> int:
    """Calculate days between two dates."""
    if isinstance(date1, str):
        date1 = parse_date(date1)
    if isinstance(date2, str):
        date2 = parse_date(date2)
        
    return (date2 - date1).days
EOF

# Create main.py
cat > src/main.py << 'EOF'
#!/usr/bin/env python
"""Main pipeline orchestration entry point."""
import sys
import os
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent))

from logging.logger import Logger
from extract.csv_reader import CSVReader
from transform.cleaning import DataCleaner
from transform.validation import DataValidator
from transform.business_rules import BusinessRules
from load.sql_loader import SQLLoader
from quality.null_checks import NullChecker
from quality.duplicate_checks import DuplicateChecker
import logging

def setup_logging():
    """Initialize logging."""
    logger = Logger('config/config.yaml')
    logger.setup()
    return logging.getLogger(__name__)

def run_pipeline():
    """Execute the ETL pipeline."""
    logger = setup_logging()
    logger.info("Starting ETL pipeline")
    
    try:
        # 1. Extract
        logger.info("Phase 1: Extraction")
        reader = CSVReader('data/raw/input.csv')
        df = reader.read()
        logger.info(f"Extracted {len(df)} rows")
        
        # 2. Transform
        logger.info("Phase 2: Transformation")
        cleaner = DataCleaner(df)
        df = cleaner.clean()
        
        # Apply business rules
        rules = BusinessRules(df)
        df = rules.apply_all()
        
        # 3. Quality Checks
        logger.info("Phase 3: Quality Checks")
        null_checker = NullChecker(df)
        null_results = null_checker.check_null_threshold(0.1)
        
        duplicate_checker = DuplicateChecker(df)
        duplicate_summary = duplicate_checker.get_duplicate_summary()
        
        # 4. Load
        logger.info("Phase 4: Loading")
        # loader = SQLLoader(connection)
        # loader.load_dataframe(df, 'target_table')
        