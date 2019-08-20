USE SourceSafe
GO

CREATE TABLE SourceSafeLog
(
       [ID] [bigint] not null  identity,
       [SourceSafeID] [int] not null ,
       [IsSuccess] [bit] not null ,
       [TimeUse] [int] not null ,
       [UpdateCount] [int] not null ,
       [ErrorCount] [int] not null ,
       [ErrorDesc] [ntext] not null ,
       [LastChangeTime] [datetime] not null ,
       [UpdateTime] [datetime] not null 
)
GO

ALTER TABLE SourceSafeLog ADD CONSTRAINT PK_SourceSafeLog PRIMARY KEY CLUSTERED
(
    ID
)
GO


