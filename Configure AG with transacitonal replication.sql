--Step 1: Configure distributor (in primary distributor)
USE master;
GO
EXECUTE sys.sp_adddistributor
    @distributor = 'WIN-FVVQ7PLR2I6',  --Primary distributor server name
    @password = 'MyPassword!';
GO

--Step 2: Configure distributor (in secondary distributor)
USE master;
GO
EXECUTE sys.sp_adddistributor
    @distributor = 'WIN-SFFBQRKDSRL',  --Secondary distributor server name
    @password = 'MyPassword!';
GO

--Step 3: Create distribution database (in primary distributor)
USE master;
GO
EXECUTE sys.sp_adddistributiondb
    @database = 'distribution',
    @security_mode = 1;

--Step 4: Add distribution database to distributionAG (in primary distributor)
ALTER DATABASE [distribution] SET RECOVERY FULL WITH NO_WAIT
GO
BACKUP DATABASE [distribution] 
TO
DISK = N'NULL' 
WITH NOFORMAT, NOINIT,
NAME = N'distribution-Full Database Backup', SKIP, NOREWIND, NOUNLOAD,
STATS = 10
GO

USE [master]
GO
ALTER AVAILABILITY GROUP [distributorAG]
MODIFY REPLICA ON N'WIN-SFFBQRKDSRL' WITH (SEEDING_MODE = AUTOMATIC)
GO

USE [master]
GO
ALTER AVAILABILITY GROUP [distributorAG]
ADD DATABASE [distribution];
GO

-- Step 5: adding distribution database (in secondary distributor)
ALTER AVAILABILITY GROUP [distributorAG] GRANT CREATE ANY DATABASE;
GO
sp_adddistributiondb 'distribution'
GO

-- Step 6: Add primary and secondary publishers (in primary distributor)
sp_adddistpublisher @publisher= 'WIN-FRLGBC5IPSH', @distribution_db= 'distribution',  --WIN-FRLGBC5IPSH is primary publisher
@working_directory= '\\WIN-FRLGBC5IPSH\sharedSnapshot' -- This location should be accessible from both primary and secondary servers
GO

sp_adddistpublisher @publisher= 'WIN-RDM2OOCJ44F', @distribution_db= 'distribution', 
@working_directory= '\\WIN-FRLGBC5IPSH\sharedSnapshot'
GO

-- Step 7: Add primary and secondary publishers (in secondary distributor)
sp_adddistpublisher @publisher= 'WIN-FRLGBC5IPSH', @distribution_db= 'distribution',  --WIN-FRLGBC5IPSH is primary publisher
@working_directory= '\\WIN-FRLGBC5IPSH\sharedSnapshot' -- This location should be accessible from both primary and secondary servers
GO

sp_adddistpublisher @publisher= 'WIN-RDM2OOCJ44F', @distribution_db= 'distribution', 
@working_directory= '\\WIN-FRLGBC5IPSH\sharedSnapshot'
GO


--Step 8: Setup publisher primary (in primary publisher)
Use MASTER
GO
sp_adddistributor @distributor = 'distributorLsnr', @password = 'MyPassword!'
GO

--Step 9: Setup publisher secondary (in secondary publisher)
Use MASTER
GO
sp_adddistributor @distributor = 'distributorLsnr', @password = 'MyPassword!'
GO

--Step 10: Enable publication in publisher database (in primary publisher)
USE master
GO
EXEC sys.sp_replicationdboption
@dbname = 'AGDB',   ---Insert your DB name here
@optname = 'publish',
@value = 'true'

--Step 11: Redirect distributor to publisher listener for all original publishers (in primary distributor)
USE distribution
GO
EXEC sys.sp_redirect_publisher
@original_publisher = 'WIN-FRLGBC5IPSH',
@publisher_db = 'AGDB',  ---Insert your DB name here
@redirected_publisher = 'publisherLsnr'
GO

USE distribution
GO
EXEC sys.sp_redirect_publisher
@original_publisher = 'WIN-RDM2OOCJ44F',
@publisher_db = 'AGDB',  ---Insert your DB name here
@redirected_publisher = 'publisherLsnr'
GO

--Step 12: Validate redirection  (in primary distributor)
USE distribution;
GO
DECLARE @redirected_publisher sysname;
EXEC sys.sp_validate_replica_hosts_as_publishers
@original_publisher = 'WIN-FRLGBC5IPSH',
@publisher_db = 'AGDB',  ---Insert your DB name here
@redirected_publisher = @redirected_publisher output;
PRINT @redirected_publisher

-- Step 13: Confirm same linked servers in both primary and secondary distributors

--Step 14: Create publication
-- Enabling the replication database
use master
exec sp_replicationdboption @dbname = N'AGDB', @optname = N'publish', @value = N'true'
GO

-- Adding the transactional publication
use [AGDB]
exec sp_addpublication @publication = N'agdbPublication', 
@description = N'Transactional publication of database ''AGDB'' from Publisher ''WIN-FRLGBC5IPSH''.',
@sync_method = N'concurrent', @retention = 0, @allow_push = N'true',
@allow_pull = N'true', @allow_anonymous = N'true', 
@enabled_for_internet = N'false', 
@snapshot_in_defaultfolder = N'true', 
@compress_snapshot = N'false', 
@ftp_port = 21, @allow_subscription_copy = N'false', 
@add_to_active_directory = N'false', 
@repl_freq = N'continuous', 
@status = N'active', 
@independent_agent = N'true',
@immediate_sync = N'true', 
@allow_sync_tran = N'false', 
@allow_queued_tran = N'false',
@allow_dts = N'false', @replicate_ddl = 1, 
@allow_initialize_from_backup = N'false',
@enabled_for_p2p = N'false', @enabled_for_het_sub = N'false'
GO


exec sp_addpublication_snapshot @publication = N'agdbPublication',
@frequency_type = 1, @frequency_interval = 1, @frequency_relative_interval = 1, 
@frequency_recurrence_factor = 0, @frequency_subday = 8, @frequency_subday_interval = 1,
@active_start_time_of_day = 0, @active_end_time_of_day = 235959, @active_start_date = 0,
@active_end_date = 0, @job_login = null, @job_password = null, @publisher_security_mode = 1


use [AGDB]
exec sp_addarticle @publication = N'agdbPublication', @article = N'Table_2', 
@source_owner = N'dbo', @source_object = N'Table_2', @type = N'logbased', 
@description = null, @creation_script = null, @pre_creation_cmd = N'drop',
@schema_option = 0x000000000803509F, @identityrangemanagementoption = N'manual',
@destination_table = N'Table_2', @destination_owner = N'dbo', 
@vertical_partition = N'false', @ins_cmd = N'CALL sp_MSins_dboTable_2', 
@del_cmd = N'CALL sp_MSdel_dboTable_2', @upd_cmd = N'SCALL sp_MSupd_dboTable_2'
GO

--Step 15: Give necessary permissions:
a. Primary and secondary's sql server agent accounts of distributor replicas should have access to publisher db as DB ownerin both primary and secondary publishers
b. rimary and secondary's sql server agent accounts of distributor replicas should have access to subscriber db as DB owner n both primary and secondary subscribers

--Step 16: Create subscriptions
use [AGDB]
exec sp_addsubscription @publication = N'agdbPublication',
@subscriber = N'SUBSCRIBERLSNR', @destination_db = N'subscriberDB',
@subscription_type = N'Push', @sync_type = N'automatic', @article = N'all',
@update_mode = N'read only', @subscriber_type = 0

exec sp_addpushsubscription_agent @publication = N'agdbPublication',
@subscriber = N'SUBSCRIBERLSNR', @subscriber_db = N'subscriberDB',
@job_login = null, @job_password = null, @subscriber_security_mode = 1,
@frequency_type = 64, @frequency_interval = 0, @frequency_relative_interval = 0, 
@frequency_recurrence_factor = 0, @frequency_subday = 0, @frequency_subday_interval = 0, 
@active_start_time_of_day = 0, @active_end_time_of_day = 235959, 
@active_start_date = 20260217, @active_end_date = 99991231,
@enabled_for_syncmgr = N'False', @dts_package_location = N'Distributor'
GO
----

--Step 17: Create subscriber listener linked server in secondary publisher and secondary distributor
--Step 18: Create  publisher linked servers in secondary distributor




