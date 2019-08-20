USE SourceSafe
GO


CREATE PROCEDURE [dbo].[getSourceSafeSetting]
AS
BEGIN
	set nocount on 

	SELECT	SourceSafeName,
			SourceType,
			DBConnectionString,
			LocalSourceCodePath,
			SourceSafeType,
			SourceSafeEXEFile,
			SourceSafeCodePath,
			Interval,
			LastUpdate,
			(CASE WHEN LastChangeTime IS NULL THEN '1900-01-01' ELSE LastChangeTime END) AS LastChangeTime,
			LastSuccessTime,
			(CASE	WHEN DATEDIFF(SECOND,LastSuccessTime,GETDATE())<3600 
					THEN 0 ELSE 1 END) AS IsFirstRun
	FROM SourceSafeSetting
	WHERE IsEnable=1

END


