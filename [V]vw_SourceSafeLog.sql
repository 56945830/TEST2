USE SourceSafe
GO

CREATE VIEW [dbo].[vw_SourceSafeLog]
AS
SELECT  a.ID, 
		b.SourceSafeName, 
		a.IsSuccess, 
		a.TimeUse, 
		a.UpdateCount, 
		a.ErrorCount,
		a.ErrorDesc, 
		a.UpdateTime, 
		a.LastChangeTime
FROM      dbo.SourceSafeLog AS a 
LEFT OUTER JOIN dbo.SourceSafeSetting AS b 
ON a.SourceSafeID = b.ID

