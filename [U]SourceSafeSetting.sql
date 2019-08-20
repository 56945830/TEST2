USE SourceSafe
GO

CREATE TABLE SourceSafeSetting
(
       [ID] [int] null,
       [SourceSafeName] [nvarchar] (50) not null ,
       [SourceType] [varchar] (20) not null ,
       [DBConnectionString] [nvarchar] (200) not null ,
       [LocalSourceCodePath] [nvarchar] (200) not null ,
       [SourceSafeType] [nvarchar] (200) not null ,
       [SourceSafeEXEFile] [nvarchar] (200) not null ,
       [SourceSafeCodePath] [nvarchar] (200) null,
       [Interval] [int] not null ,
       [IsEnable] [bit] not null ,
       [LastUpdate] [datetime] null,
       [LastChangeTime] [datetime] null,
       [LastSuccessTime] [datetime] null,
       [IsLastSuccess] [bit] null
)
GO

ALTER TABLE SourceSafeSetting ADD CONSTRAINT PK_SourceSafeSetting PRIMARY KEY CLUSTERED
(
    SourceSafeName
)
GO


