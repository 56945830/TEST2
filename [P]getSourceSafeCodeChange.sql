USE SourceSafe
GO




--本存储用于自动源代码管理获取，需要在目标库上建立


CREATE PROCEDURE [dbo].[getSourceSafeCodeChange] 
@p_Init				INT,		--是否初始化，除了取变更外还取全部数据库对象
@p_BeginTime		DATETIME,	--跟踪监测起始时间
@p_CheckTrace		INT		 OUTPUT,--服务器是否开启了跟踪
@p_LastChangeTime   DATETIME OUTPUT	--最后源代码变更时间，下次监测起始时间从这个时间开始
AS

--DECLARE @p_Init				INT
--DECLARE @p_BeginTime		DATETIME
--DECLARE @p_CheckTrace		INT
--DECLARE @p_LastChangeTime   DATETIME
--SET @p_Init=0
--SET @p_BeginTime='20190315'

BEGIN
	SET NOCOUNT ON 




	--判断是否开启了跟踪
	SELECT @p_CheckTrace=convert(int,value_in_use)
	FROM sys.configurations 
	WHERE name = 'default trace enabled'


	IF @p_CheckTrace=1
	BEGIN
		
		--记录变更记录
		CREATE TABLE #Temp_SourceCode (
			DBName			NVARCHAR(50),	--数据库名称
			ObjName			NVARCHAR(256)	NOT NULL,	--对象名称
			ObjectType		VARCHAR(10)		NOT NULL,   --类型名称
			ObjectId		INT,
			LastChangeTime	DATETIME,		--最后变更时间
			LastOperation	NVARCHAR(40),	--最后操作
			OperationText	NVARCHAR(MAX),	--变更操作详细记录
			SourceCode		NVARCHAR(MAX)	--对象源代码
			PRIMARY KEY(DBName,ObjName,ObjectType)
		);


		--通过日志取变更记录和变更人
		CREATE TABLE #TempTrace (
			DBName			NVARCHAR(50),	--数据库名称
			ObjName			NVARCHAR(256),	--对象名称
			ObjectType		NVARCHAR(10),			
			ObjectId		INT,
			ChangeTime		DATETIME,		--变更时间
			Operation		NVARCHAR(40) ,	--变更操作
			ServerName		NVARCHAR(256),	
			LoginName		NVARCHAR(256),
			ApplicationName NVARCHAR(256)
		);

		DECLARE @curr_tracefilename VARCHAR(500);  
		DECLARE @base_tracefilename VARCHAR(500);  
		DECLARE @indx int ; 

		SELECT @curr_tracefilename = path FROM sys.traces WHERE is_default = 1 ;  
		SET @curr_tracefilename = REVERSE(@curr_tracefilename) 
		SELECT @indx  = PATINDEX('%\%', @curr_tracefilename) 
		SET @curr_tracefilename = REVERSE(@curr_tracefilename) 
		SET @base_tracefilename = LEFT( @curr_tracefilename,LEN(@curr_tracefilename) - @indx) + '\log.trc'; 




		INSERT INTO #TempTrace 
		SELECT  DB_NAME(a.DatabaseID)
		,		(CASE	WHEN OBJECT_SCHEMA_NAME(ObjectID)!='dbo' 
						THEN OBJECT_SCHEMA_NAME(ObjectID)+'.'
						ELSE ''
				END)+a.ObjectName AS ObjectName
		,       (CASE	WHEN a.ObjectType=17993	THEN 'IF'
						WHEN a.ObjectType=18004	THEN 'TF'
						WHEN a.ObjectType=20038	THEN 'FN'
						WHEN a.ObjectType=8272	THEN 'P'
						WHEN a.ObjectType=8277	THEN 'U' 
						WHEN a.ObjectType=8278	THEN 'V'	
						WHEN a.ObjectType=22868	THEN 'TT' END) AS ObjectType
		,		a.ObjectID
		,       a.StartTime
		,       (CASE	WHEN a.EventClass=46	THEN 'CREATE'
						WHEN a.EventClass=47	THEN 'DROP'
						WHEN a.EventClass=164 THEN 'ALTER' END)
		,       a.ServerName
		,       a.LoginName
		,       a.ApplicationName
		FROM ::fn_trace_gettable( @base_tracefilename, default )  a
		LEFT OUTER JOIN sys.objects b
		ON a.ObjectID=b.object_id
		WHERE a.EventClass in (46,47,164) 
		AND a.EventSubclass = 0  
		AND a.DatabaseID = db_id()
		AND a.ObjectType IN ('17993','20038','8272','8277','8278','22868','18004')
		AND (b.type!='S' OR b.type IS NULL)  /*有些系统表会被弄进来，原因不明*/
		--where ObjectType not in (21587) -- don''t bother with auto-statistics as it generates too much noise
		


		;WITH Temp AS(
			SELECT  DBName,
					ObjName,
					ObjectType,
					ObjectId,
					ChangeTime,
					Operation,
					'变更时间:'+ CONVERT(NVARCHAR(20),ChangeTime,120)+ ' 操作账号：'+LoginName+' 变更操作：'+Operation+' 服务器名称：'+ServerName AS OperationText
			FROM #TempTrace
			WHERE ChangeTime>@p_BeginTime
			OR @p_Init=1
		)
		,Temp2 AS(
			SELECT	DBName,
					ObjName,
					ObjectType,
					MAX(ObjectId) AS ObjectID,
					MAX(ChangeTime) AS LastChangeTime,
					(	SELECT OperationText+CHAR(10)
						FROM Temp 
						WHERE ObjName=a.ObjName AND ObjectType=a.ObjectType
						FOR XML PATH('')) AS OperationText
			FROM Temp a
			GROUP BY DBName,ObjName,ObjectType
		)
		INSERT #Temp_SourceCode(DBName,ObjName,ObjectType,ObjectId,LastChangeTime,LastOperation,OperationText)
		SELECT	a.DBName,
				a.ObjName,
				a.ObjectType,
				a.ObjectID,
				a.LastChangeTime,
				b.Operation AS LastOperation,
				a.OperationText
		FROM Temp2 a
		OUTER APPLY (	SELECT TOP 1 * 
						FROM Temp
						WHERE ObjName=a.ObjName
						AND ObjectType=a.ObjectType
						AND ChangeTime=a.LastChangeTime) b


		--取所有不在数据库变更记录中的数据库对象
		IF @p_Init=1
		BEGIN 
			--取数据库对象内容
			IF EXISTS(SELECT * FROM sys.sysobjects WHERE type='TT')/*如果存在UDTT（2008+）则名称需要从table_types里面取名称*/
			BEGIN
				;WITH Temp AS(
					SELECT	(CASE	WHEN OBJECT_SCHEMA_NAME(a.id)!='dbo' 
									THEN OBJECT_SCHEMA_NAME(a.id)+'.'
									ELSE ''
							END)+ISNULL(b.name,a.name) AS ObjName,
							a.xtype AS ObjectType,
							id AS ObjectId,
							'1900-01-01' AS LastChangeTime,
							'' AS LastOperation,
							'初始化源代码' AS OperationText
					FROM sys.sysobjects a
					LEFT OUTER JOIN sys.table_types b
					ON a.id=b.type_table_object_id
					WHERE a.xtype IN ('IF','TF','FN','P','U','V','TT')
				)
				INSERT #Temp_SourceCode(DBName,ObjName,ObjectType,ObjectId,LastChangeTime,LastOperation,OperationText)
				SELECT DB_NAME(),a.ObjName,a.ObjectType,a.ObjectId,a.LastChangeTime,a.LastOperation,a.OperationText 
				FROM Temp a
				LEFT OUTER JOIN #Temp_SourceCode b
				ON a.ObjName=b.ObjName
				AND a.ObjectType=b.ObjectType
				WHERE b.ObjName IS NULL
			END
			ELSE
			BEGIN
				;WITH Temp AS(
					SELECT	(CASE	WHEN OBJECT_SCHEMA_NAME(a.id)!='dbo' 
									THEN OBJECT_SCHEMA_NAME(a.id)+'.'
									ELSE ''
							END)+a.name AS ObjName,
							a.xtype AS ObjectType,
							id AS ObjectId,
							'1900-01-01' AS LastChangeTime,
							'' AS LastOperation,
							'初始化源代码' AS OperationText
					FROM sys.sysobjects a
					WHERE a.xtype IN ('IF','TF','FN','P','U','V','TT')
				)
				INSERT #Temp_SourceCode(DBName,ObjName,ObjectType,ObjectId,LastChangeTime,LastOperation,OperationText)
				SELECT DB_NAME(),a.ObjName,a.ObjectType,a.ObjectId,a.LastChangeTime,a.LastOperation,a.OperationText 
				FROM Temp a
				LEFT OUTER JOIN #Temp_SourceCode b
				ON a.ObjName=b.ObjName
				AND a.ObjectType=b.ObjectType
				WHERE b.ObjName IS NULL
			END
		
		END


		--取源代码
		--存储过程，函数
		UPDATE a
		SET SourceCode='USE '+a.DBName+'
'+'GO'+'
'+ISNULL(definition,'')
		FROM #Temp_SourceCode a
		LEFT OUTER JOIN sys.sql_modules b
		ON a.ObjectId=b.object_id
		WHERE ObjectType!='U'
		

		--生成表建表脚本
		DECLARE @l_sql NVARCHAR(max)
		declare @table_script nvarchar(max) --建表的脚本
		declare @index_script nvarchar(max) --索引的脚本
		declare @default_script nvarchar(max) --默认值约束的脚本
		declare @sql_cmd nvarchar(max)  --动态SQL命令
		DECLARE @l_TableName NVARCHAR(100)
		WHILE EXISTS(	SELECT * 
						FROM #Temp_SourceCode
						WHERE ObjectType='U' AND SourceCode IS NULL )
		BEGIN
			SELECT @l_TableName=ObjName 
			FROM #Temp_SourceCode
			WHERE ObjectType='U' AND SourceCode IS NULL
        
			--判断表是否存在
			IF EXISTS (SELECT * FROM sys.objects 
							WHERE object_id=OBJECT_ID(@l_TableName))
			BEGIN 
		  		----------------------生成创建表脚本----------------------------
				--1.添加算定义字段
				set @table_script = 'CREATE TABLE '+@l_TableName+'
('+char(13)+char(10);
 
 
				--添加表中的其它字段
				set @sql_cmd=N'
				set @table_script='''' 
				select @table_script=@table_script+
						''       [''+t.NAME+''] ''
						+(case when t.xusertype in (175,62,239,59,122,165,173) then ''[''+p.name+''] (''+convert(varchar(30),isnull(t.prec,''''))+'')''
							  when t.xusertype in (231) and t.length=-1 then ''[ntext]''
							  when t.xusertype in (231) and t.length<>-1 then ''[''+p.name+''] (''+convert(varchar(30),isnull(t.prec,''''))+'')''
							 when t.xusertype in (167) and t.length=-1 then ''[text]''
							  when t.xusertype in (167) and t.length<>-1 then ''[''+p.name+''] (''+convert(varchar(30),isnull(t.prec,''''))+'')''
							  when t.xusertype in (106,108) then ''[''+p.name+''] (''+convert(varchar(30),isnull(t.prec,''''))+'',''+convert(varchar(30),isnull(t.scale,''''))+'')''
							  else ''[''+p.name+'']''
						 END)
						 +(case when t.isnullable=1 then '' null'' else '' not null ''end)
						 +(case when COLUMNPROPERTY(t.ID, t.NAME, ''ISIDENTITY'')=1 then '' identity'' else '''' end)
						 +'',''+char(13)+char(10)
				from syscolumns t join systypes p  on t.xusertype = p.xusertype
				where t.ID=OBJECT_ID('''+@l_TableName+''')
				ORDER BY  t.COLID; 
				'
				EXEC sp_executesql @sql_cmd,N'@table_script varchar(max) output',@sql_cmd output
				set @table_script=@table_script+@sql_cmd

				IF len(@table_script)>0
					set @table_script=substring(@table_script,1,len(@table_script)-3)+char(13)+char(10)
						+')'+char(13)+char(10)
						+'GO'+char(13)+char(10)+char(13)+char(10)
			
			
				--------------------生成索引脚本---------------------------------------
				set @index_script=''
				set @sql_cmd=N'
				declare @ct int
				declare @indid int      --当前索引ID
				declare @p_indid int    --前一个索引ID
				select @indid=-1, @p_indid=0,@ct=0    --初始化，以后用@indid和@p_indid判断是否索引ID发生变化
				set @index_script=''''
				select @indid=index_id
				,@index_script=@index_script
				+(case when @indid<>@p_indid and @ct>0 then '')''+char(13)+char(10)+''GO''+char(13)+char(10) else '''' end)
				+(case when @indid<>@p_indid and UNIQ=''PRIMARY KEY'' 
						then ''ALTER TABLE ''+TABNAME+'' ADD CONSTRAINT ''+name+'' PRIMARY KEY ''+CLUSTER+char(13)+char(10)
							+''(''+char(13)+char(10)
							+''    ''+COLNAME+char(13)+char(10)
						when @indid<>@p_indid and UNIQ=''UNIQUE'' 
						then ''ALTER TABLE ''+TABNAME+'' ADD CONSTRAINT ''+name+'' UNIQUE ''+CLUSTER+char(13)+char(10)
							+''(''+char(13)+char(10)
							+''    ''+COLNAME+char(13)+char(10)
						when @indid<>@p_indid and UNIQ=''INDEX''     
						then ''CREATE ''+CLUSTER+'' INDEX ''+name+'' ON ''+TABNAME+char(13)+char(10)
							+''(''+char(13)+char(10)
							+''    ''+COLNAME+char(13)+char(10)
						when @indid=@p_indid
						then  ''    ,''+COLNAME+char(13)+char(10)
					END) 
				,@ct=@ct+1
				,@p_indid=@indid
				from 
				(
				SELECT A.index_id,B.keyno
					,name,OBJECT_NAME(object_id) AS TABNAME,
					(SELECT name FROM sys.columns WHERE object_id=B.id AND column_id=B.colid) AS COLNAME,
					(CASE WHEN EXISTS(SELECT 1 FROM sys.objects WHERE name=A.name AND type=''UQ'') THEN ''UNIQUE'' 
							WHEN EXISTS(SELECT 1 FROM sys.objects WHERE name=A.name AND type=''PK'') THEN ''PRIMARY KEY''
							ELSE ''INDEX'' END)  AS UNIQ,
					(CASE WHEN A.index_id=1 THEN ''CLUSTERED'' WHEN A.index_id>1 THEN ''NONCLUSTERED'' END) AS CLUSTER
				FROM sys.indexes A INNER JOIN sys.sysindexkeys B ON A.index_id=B.indid AND A.object_id=B.id
				WHERE A.object_id=OBJECT_ID('''+@l_TableName+''') and A.index_id<>0
				) t
				ORDER BY index_id,keyno'


				EXEC sp_executesql @sql_cmd,N'@index_script varchar(max) output',@sql_cmd output
				set @index_script=@sql_cmd
				IF len(@index_script)>0
				set @index_script=@index_script+')'+char(13)+char(10)+'GO'+char(13)+char(10)+char(13)+char(10)


				--生成默认值约束
				set @sql_cmd='
				set @default_script=''''
				SELECT @default_script=@default_script
						+''ALTER TABLE ''+OBJECT_NAME(O.parent_object_id)
						+'' ADD CONSTRAINT ''+O.name+'' default ''+T.text+'' for ''+C.name+char(13)+char(10)
						+''GO''+char(13)+char(10)
				FROM sys.objects O INNER JOIN syscomments T ON O.object_id=T.id
					INNER JOIN syscolumns C ON O.parent_object_id=C.id AND C.cdefault=T.id
				WHERE O.type=''D'' AND O.parent_object_id=OBJECT_ID('''+@l_TableName+''')'
				EXEC sp_executesql @sql_cmd,N'@default_script varchar(max) output',@sql_cmd output
				set @default_script=@sql_cmd+char(13)+char(10)

				SET @l_sql=@table_script+ISNULL(@index_script,'')+ISNULL(@default_script,'')

				IF @l_TableName='qdii_fund_state'
				BEGIN 
					PRINT @table_script
					PRINT @index_script
					PRINT @default_script
				END 

				UPDATE  #Temp_SourceCode
				SET SourceCode= 'USE '+DBName+'
'+'GO'+'

'+@l_sql
				WHERE ObjectType='U' 
				AND SourceCode IS NULL
				AND ObjName=@l_TableName 

			END 
			ELSE 
			BEGIN 
				UPDATE  #Temp_SourceCode
				SET SourceCode= 'TABLE IS DROPPED'
				WHERE ObjectType='U' 
				AND SourceCode IS NULL
				AND ObjName=@l_TableName 
			END 
			print @l_TableName
		END       


		--如果没有最后变更记录，则使用当前时间向前推一分钟
		SELECT @p_LastChangeTime=ISNULL(MAX(LastChangeTime),GETDATE()-1.0/24/60)
		FROM #Temp_SourceCode
        

		SELECT	DBName,
				REPLACE(ObjName,' ','') AS ObjName,
				RTRIM(ObjectType) AS ObjectType,
				ObjectId,
				LastChangeTime,
				LastOperation,
				OperationText,
				SourceCode
		FROM #Temp_SourceCode 
		--order by ChangeTime desc;

	END 


END

