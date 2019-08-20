USE SourceSafe
GO


CREATE PROCEDURE [dbo].[updSourceSafeLog] 
@p_SourceSafeName	NVARCHAR(50),		
@p_IsSuccess		BIT,
@p_TimeUse			INT,
@p_UpdateCount		INT,
@p_ErrorCount		INT,
@p_ErrorDesc		NVARCHAR(MAX),
@p_LastChangeTime	DATETIME
AS
BEGIN
	
	DECLARE @l_SourceSafeID INT
	
	SELECT @l_SourceSafeID=ID
	FROM SourceSafeSetting
	WHERE SourceSafeName=@p_SourceSafeName






	INSERT SourceSafeLog(SourceSafeID,IsSuccess,TimeUse,UpdateCount,ErrorCount,ErrorDesc,LastChangeTime,UpdateTime)
	VALUES(@l_SourceSafeID,@p_IsSuccess,@p_TimeUse,@p_UpdateCount,@p_ErrorCount,@p_ErrorDesc,@p_LastChangeTime,GETDATE())

	IF @p_IsSuccess=1
	BEGIN
		UPDATE SourceSafeSetting
		SET LastUpdate=GETDATE(),
			LastChangeTime=@p_LastChangeTime,
			IsLastSuccess=@p_IsSuccess,
			LastSuccessTime=GETDATE()
		WHERE SourceSafeName=@p_SourceSafeName

	END
	ELSE
	BEGIN
		UPDATE SourceSafeSetting
		SET LastUpdate=GETDATE(),
			IsLastSuccess=@p_IsSuccess
		WHERE SourceSafeName=@p_SourceSafeName
	END


END
