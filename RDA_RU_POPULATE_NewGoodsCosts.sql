
USE [ReportsView]
GO 

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:          Alicia Jorda
-- Create date:     07/30/2021
-- Change Log:
--      8/2/2021 aj
--          -Refactored to run off the @FirstDayOfMonth var.
-- 			-First save to ReportsView, first run for July 2021 data
--      8/4/2021 aj
--          -Switched Online Sales to use ShipDate, instead of OrderDate.
--      8/5/2021 aj
--          -Refactored scan/frln/dist logic into its own table: RDA_NewGoodsCosts_PTypeCategory
--TODO      -Add links to OFS for HPB.com sales, since those can cross ship, too
-- Description:	Updates/Inserts to RDA_RU_NewGoodsCosts
-- =============================================
ALTER PROCEDURE [dbo].[RDA_RU_Populate_NewGoodsCosts]

-- Add the parameters for the stored procedure here
			@FirstDayOfMonth date
-- declare	@FirstDayOfMonth date = datefromparts(year(getdate()),month(getdate())-1,1)

-- AS 
-- BEGIN 

-- SET NOCOUNT ON;

declare @StartDate 	date
declare @EndDate    date

-- If @FirstDayOfMonth is passed, roll up only the month of @FirstDayOfMonth. 
if @FirstDayOfMonth is not null begin
    set @StartDate = datefromparts(year(@FirstDayOfMonth),month(@FirstDayOfMonth),1)
    set @EndDate = dateadd(month, 1, @StartDate)
end

-- Otherwise, roll-up all months in last 3+ years 
-- ...or however many years are in rHPB_Historical..SalesItemHistory_Recent
if @FirstDayOfMonth is null begin
    --Since this PARAMS_CreateDateRangeSelect generates the list of selectable dates for the report, 
    --it is used to set @StartDate and @EndDate.
    set @StartDate = datefromparts(year(getdate())-3,1,1)
    set @EndDate   = datefromparts(year(getdate()),month(getdate()),1)
end


--Component temp table creation--------------------------------
---------------------------------------------------------------
drop table if exists #Sales_prep
create table #Sales_prep(
    BusinessMonth date
    ,LocationNo varchar(30)
    ,SldTy int
    ,PrCat varchar(5)
    ,Qty int
    ,Cost money
    ,Val money
    ,Fee money)
					
drop table if exists #Sales
create table #Sales(
    BusinessMonth date
    ,LocationNo varchar(30)
    ,DistSoldCost money
    ,DistSoldVal money
    ,FrlnSoldCost money
    ,FrlnSoldVal money
    ,ScanSoldQty int
    ,ScanSoldCost money
    ,ScanSoldVal money
    ,sDistSoldCost money
    ,sDistSoldVal money
    ,sFrlnSoldCost money
    ,sFrlnSoldVal money
    ,sScanSoldQty int
    ,sScanSoldCost money
    ,sScanSoldVal money
    ,oDistSoldCost money
    ,oDistSoldVal money
    ,oFrlnSoldCost money
    ,oFrlnSoldVal money
    ,oScanSoldQty int
    ,oScanSoldCost money
    ,oScanSoldVal money
    ,bwDistSoldCost money
    ,bwDistSoldVal money
    ,bwFrlnSoldCost money
    ,bwFrlnSoldVal money
    ,bwScanSoldQty int
    ,bwScanSoldCost money
    ,bwScanSoldVal money)

drop table if exists #Xfers_prep
create table #Xfers_prep(
    BusinessMonth date
    ,LocationNo varchar(30)
    ,XfrTy int
    ,PrCat varchar(5)
    ,Qty int
    ,Cost money)

drop table if exists #Xfers
create table #Xfers(
    BusinessMonth date
    ,LocationNo varchar(30)
    ,DistTshQty int
    ,DistTshCost money
    ,DistDmgQty int
    ,DistDmgCost money
    ,DistDntQty int
    ,DistDntCost money
    ,TotDistRfiQty int
    ,TotDistRfiCost money
    ,DistOStSQty int
    ,DistOStSCost money
    ,DistIStSQty int
    ,DistIStSCost money
    ,FrlnTshQty int
    ,FrlnTshCost money
    ,FrlnDmgQty int
    ,FrlnDmgCost money
    ,FrlnDntQty int
    ,FrlnDntCost money
    ,TotFrlnRfiQty int
    ,TotFrlnRfiCost money
    ,FrlnOStSQty int
    ,FrlnOStSCost money
    ,FrlnIStSQty int
    ,FrlnIStSCost money)

drop table if exists #KeyTable 
select BusinessMonth,LocationNo
into #KeyTable 
from ReportsView..RDA_RU_NewGoodsCosts 
where 1 = 0


--Collect Brick & Mortar Sales Data-------------------------------------------
------------------------------------------------------------------------------
insert into #Sales_prep
select 
    datefromparts(year(sih.BusinessDate),month(sih.BusinessDate),1)[BusinessMonth]
	,loc.LocationNo
	,1[SldTy]
	,pc.PTypeCategory[PrCat]
	,sum(sih.Quantity * case when sih.IsReturn = 'Y' then -1 else 1 end)[Qty]
	,sum(sih.Quantity * pm.Cost * case when sih.IsReturn = 'Y' then -1 else 1 end)[Cost]
	,sum(sih.ExtendedAmt)[Val]
	,cast(0 as money)[Fee]
from rHPB_Historical..SalesHeaderHistory_Recent shh 
	inner join rHPB_Historical..SalesItemHistory_Recent sih 
		on sih.LocationID = shh.LocationID
		and sih.BusinessDate = shh.BusinessDate
		and sih.SalesXactionId = shh.SalesXactionID
	inner join ReportsData..Locations loc on sih.LocationID = loc.LocationID
	inner join ReportsData..ProductMaster pm on sih.ItemCode = pm.Itemcode 
	inner join ReportsView..RDA_NewGoodsCosts_PTypeCategory pc on pm.ProductType = pc.ProductType 
where shh.Status = 'A'
	and shh.XactionType = 'S'
	and sih.BusinessDate >= @StartDate
	and sih.BusinessDate < @EndDate
	and pc.PTypeClass = 'NEW'
	and pc.PTypeCategory <> 'gc'
group by 
    datefromparts(year(sih.BusinessDate),month(sih.BusinessDate),1)
	,loc.LocationNo
	,pc.PTypeCategory



-- Collect iStore Online Sales Data----------------------------
---------------------------------------------------------------
-- Shipped data--------
insert into #Sales_prep
select 
    datefromparts(year(om.ShipDate),month(om.ShipDate),1)[BusinessMonth]
    ,isnull(od.LocationNo,fa.HPBLocationNo)[LocationNo]
	,2[SldTy]
	,pc.PTypeCategory[PrCat]
	,sum(om.ShippedQuantity)[Qty]
	,sum(pm.Cost)[Cost]
	,sum(om.Price)[Val]
	,sum(om.ShippingFee)[Fee]
from isis..Order_Monsoon om 
	inner join isis..App_Facilities fa on om.FacilityID = fa.FacilityID
	--pre-2014ish, SAS & XFRs would show up in Monsoon, so specifying 'MON' excludes those
	inner join ReportsData..OFS_Order_Header oh on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'MON' 
	--Grabs fulfilment location where available, otherwise uses originating location
	inner join ReportsData..OFS_Order_Detail od on oh.OrderID = od.OrderID and od.Status in (1,4)
		--Problem orders have ProblemStatusID not null
		and (od.ProblemStatusID is null or od.ProblemStatusID = 0)	
	inner join ReportsData..ProductMaster pm on right(om.SKU,20) = pm.ItemCode
	inner join ReportsView..RDA_NewGoodsCosts_PTypeCategory pc on pm.ProductType = pc.ProductType 
where om.ShippedQuantity > 0
	and om.OrderStatus in ('New','Pending','Shipped')
	and om.ShipDate < @EndDate 
	and om.ShipDate >= @StartDate 
	and left(om.SKU,1) = 'D'
group by 
    datefromparts(year(om.ShipDate),month(om.ShipDate),1)
    ,isnull(od.LocationNo,fa.HPBLocationNo)
	,pc.PTypeCategory

-- Refunds data--------
insert into #Sales_prep
select 
    datefromparts(year(om.RefundDate),month(om.RefundDate),1)[BusinessMonth]
    ,isnull(od.LocationNo,fa.HPBLocationNo)[LocationNo]
	,-2[SldTy]
	,pc.PTypeCategory[PrCat]
	--Think refunded product doesn't go back to the store per se... 
	,0[Qty] 
	,0[Cost]
	,-sum(om.RefundAmount)[Val]
	,0[Fee]
from isis..Order_Monsoon om 
	inner join isis..App_Facilities fa on om.FacilityID = fa.FacilityID
	--pre-2014ish, SAS & XFRs would show up in Monsoon, so this excludes those
	inner join ReportsData..OFS_Order_Header oh on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'MON' 
	--Grabs fulfilment location where available, otherwise uses originating location
	inner join ReportsData..OFS_Order_Detail od on oh.OrderID = od.OrderID and od.Status in (1,4)
		--Problem orders have ProblemStatusID not null
		and (od.ProblemStatusID is null or od.ProblemStatusID = 0)	
	inner join ReportsData..ProductMaster pm on right(om.SKU,20) = pm.ItemCode
	inner join ReportsView..RDA_NewGoodsCosts_PTypeCategory pc on pm.ProductType = pc.ProductType 
where om.OrderStatus in ('New','Pending','Shipped')
	and om.RefundAmount > 0
	and om.RefundDate < @EndDate 
	and om.RefundDate >= @StartDate
	and left(om.SKU,1) = 'D'
group by 
    datefromparts(year(om.RefundDate),month(om.RefundDate),1)
    ,isnull(od.LocationNo,fa.HPBLocationNo)
	,pc.PTypeCategory


-- Collect HPB.com Online Sales Data---------------------------
---------------------------------------------------------------
-- Shipped data--------
insert into #Sales_prep
select 
    datefromparts(year(om.ShipDate),month(om.ShipDate),1)[BusinessMonth]
    ,fa.HPBLocationNo[LocationNo]
    -- ,isnull(od.LocationNo,fa.HPBLocationNo)[LocationNo]
	,3[SldTy]
	,pc.PTypeCategory[PrCat]
	,sum(om.Quantity)[Qty]
	,sum(pm.Cost)[Cost]
	,sum(om.ExtendedAmount)[Val]
	,sum(om.ShippingAmount)[Fee]
from isis..Order_Omni om 
	inner join isis..App_Facilities fa on om.FacilityID = fa.FacilityID
	inner join ReportsData..ProductMaster pm on right(om.SKU,20) = pm.ItemCode
	inner join ReportsView..RDA_NewGoodsCosts_PTypeCategory pc on pm.ProductType = pc.ProductType 
	-- inner join ReportsData..OFS_Order_Header oh on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'HMP' and om.MarketOrderID = oh.MarketOrderID
	-- --Grabs fulfilment location where available, otherwise uses originating location
	-- inner join ReportsData..OFS_Order_Detail od on oh.OrderID = od.OrderID and od.Status in (1,4) and od.ProblemStatusID is null 
where om.OrderStatus not in ('canceled')
	and om.ItemStatus = 'shipped'
    and om.ShippingMethod <> '222'
	and om.ShipDate < @EndDate 
	and om.ShipDate >= @StartDate 
	and left(om.SKU,1) = 'D'
	and om.Quantity > 0
group by 
    datefromparts(year(om.ShipDate),month(om.ShipDate),1)
    ,fa.HPBLocationNo
    -- ,isnull(od.LocationNo,fa.HPBLocationNo)
	,pc.PTypeCategory

-- Refunds data--------
insert into #Sales_prep
select 
    datefromparts(year(om.SiteLastModifiedDate),month(om.SiteLastModifiedDate),1)[BusinessMonth]
    ,fa.HPBLocationNo[LocationNo]
    -- ,isnull(od.LocationNo,fa.HPBLocationNo)[LocationNo]
	,-3[SldTy]
	,pc.PTypeCategory[PrCat]
	--Same idea... don't think we actually get the thing back to the store.
	,0[Qty] 
	,0[Cost]
	,-sum(om.ItemRefundAmount)[Val]
	,0[Fee]
from isis..Order_Omni om 
	inner join isis..App_Facilities fa on om.FacilityID = fa.FacilityID 
	inner join ReportsData..ProductMaster pm on right(om.SKU,20) = pm.ItemCode
	inner join ReportsView..RDA_NewGoodsCosts_PTypeCategory pc on pm.ProductType = pc.ProductType 
	-- inner join ReportsData..OFS_Order_Header oh on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'HMP' and om.MarketOrderID = oh.MarketOrderID
	-- --Grabs fulfilment location where available, otherwise uses originating location
	-- inner join ReportsData..OFS_Order_Detail od on oh.OrderID = od.OrderID and od.Status in (1,4) and od.ProblemStatusID is null 
where om.OrderStatus not in ('canceled')
	and om.ItemStatus = 'shipped'
    and om.ShippingMethod <> '222'
	and om.SiteLastModifiedDate < @EndDate 
	and om.SiteLastModifiedDate >= @StartDate 								  
	and left(om.SKU,1) = 'D'
	and om.Quantity > 0
	and om.ItemRefundAmount > 0
group by 
    datefromparts(year(om.SiteLastModifiedDate),month(om.SiteLastModifiedDate),1)
    ,fa.HPBLocationNo
    -- ,isnull(od.LocationNo,fa.HPBLocationNo)
	,pc.PTypeCategory



--Collect Brick & Mortar Bookworm REGISTER Data-------------------------------
------------------------------------------------------------------------------
insert into #Sales_prep
select 
    cast(dateadd(MM,datediff(MM,0,sih.BusinessDate),0) as date)[BusinessMonth]
    ,bw.LocationNo
	,0[SldTy]
	,pc.PTypeCategory[PrCat]
	,sum(sih.Quantity * case when sih.IsReturn = 'Y' then -1 else 1 end)[Qty]
	,sum(sih.Quantity * pm.Cost * case when sih.IsReturn = 'Y' then -1 else 1 end)[Cost]
	,sum(sih.ExtendedAmt)[Val]
	,0[Fee]
	-- TODO: There exist discrepancies between the Bookworm Cart record & the register sales record.
	-- TODO: the LEAST of which is Ship Fees & all taxes are rolled into the ExtAmt on the register sales record
	-- TODO: Additionally, Bookworm register sales fall under item 10222778, 
	-- TODO: ...classed under the USED  Product Type Group, & under the SPECIAL Product Type Class.
	-- ,sum(bw.price)[bwVal]
	-- ,sum(case when sih.ExtendedAmt = 0 then bw.price else 0 end)[bwZeroVal]
	-- ,sum(bw.tax)[bwTax]
	-- ,sum(bw.shippingcharge)[bwShipFee]
	-- ,sum(bw.shippingtax)[bwShipTax]
from rHPB_Historical..SalesHeaderHistory_Recent shh 
    inner join rHPB_Historical..SalesItemHistory_Recent sih 
        on sih.LocationID = shh.LocationID
        and sih.BusinessDate = shh.BusinessDate
        and sih.SalesXactionId = shh.SalesXactionID
    inner join ReportsData..BookWormOrders bw 
        on sih.LocationID = bw.locationId
        and sih.SalesXactionId = bw.tillnumber + right('000000000' + bw.transactionNumber,9) 
        and sih.LineNumber = bw.detailNumber
    inner join ReportsData..ProductMaster pm on right(replicate('0', 20) + bw.SKU, 20) = pm.ItemCode 
	inner join ReportsView..RDA_NewGoodsCosts_PTypeCategory pc on pm.ProductType = pc.ProductType 
where shh.Status = 'A'
    and shh.XactionType = 'S'
	and sih.BusinessDate >= @StartDate
	and sih.BusinessDate < @EndDate
	and pc.PTypeClass = 'NEW'
	and pc.PTypeCategory <> 'gc'
	and sih.ItemCode = '00000000000010222778' 
group by 
    cast(dateadd(MM,datediff(MM,0,sih.BusinessDate),0) as date)
    ,bw.LocationNo
	,pc.PTypeCategory




--Combine all Sales Data-------------------------------------------
-------------------------------------------------------------------
insert into #Sales
select BusinessMonth
	,LocationNo
	--Distribution-only product.....
	,sum(case when PrCat in ('dist','scan') then pr.Cost else 0 end)[DistSoldCost]
	,sum(case when PrCat in ('dist','scan') then pr.Val else 0 end)[DistSoldVal]
	-- Alternate that rolls in Shipping Fees....
	-- ,sum(case when PrCat in ('dist','scan') then pr.Val + pr.Fee else 0 end)[DistSoldVal]
	--Frontline-only product....
	,sum(case when PrCat = 'frln' then pr.Cost else 0 end)[FrlnSoldCost]
	,sum(case when PrCat = 'frln' then pr.Val else 0 end)[FrlnSoldVal]
	-- Alternate that rolls in Shipping Fees....
	-- ,sum(case when PrCat = 'dist' then pr.Val + pr.Fee else 0 end)[FrlnSoldVal]
	--Scan-only data...
	,sum(case when PrCat = 'scan' then pr.Qty else 0 end)[ScanSoldQty]
	,sum(case when PrCat = 'scan' then pr.Cost else 0 end)[ScanSoldCost]
	,sum(case when PrCat = 'scan' then pr.Val else 0 end)[ScanSoldVal]
	-- Alternate that rolls in Shipping Fees....
	-- ,sum(case when PrCat = 'scan' then pr.Val + pr.Fee else 0 end)[ScanSoldVal]

	-- B&M Sales Only...
	--Distribution-only product.....
	,sum(case when PrCat in ('dist','scan') and SldTy = 1 then pr.Cost else 0 end)[sDistSoldCost]
	,sum(case when PrCat in ('dist','scan') and SldTy = 1 then pr.Val else 0 end)[sDistSoldVal]
	--Frontline-only product....
	,sum(case when PrCat = 'frln' and SldTy = 1 then pr.Cost else 0 end)[sFrlnSoldCost]
	,sum(case when PrCat = 'frln' and SldTy = 1 then pr.Val else 0 end)[sFrlnSoldVal]
	--Scan-only data...
	,sum(case when PrCat = 'scan' and SldTy = 1 then pr.Qty else 0 end)[sScanSoldQty]
	,sum(case when PrCat = 'scan' and SldTy = 1 then pr.Cost else 0 end)[sScanSoldCost]
	,sum(case when PrCat = 'scan' and SldTy = 1 then pr.Val else 0 end)[sScanSoldVal]

	-- Online Sales Only...
	--Distribution-only product.....
	,sum(case when PrCat in ('dist','scan') and abs(SldTy) > 1 then pr.Cost else 0 end)[oDistSoldCost]
	,sum(case when PrCat in ('dist','scan') and abs(SldTy) > 1 then pr.Val else 0 end)[oDistSoldVal]
	--Frontline-only product....
	,sum(case when PrCat = 'frln' and abs(SldTy) > 1 then pr.Cost else 0 end)[oFrlnSoldCost]
	,sum(case when PrCat = 'frln' and abs(SldTy) > 1 then pr.Val else 0 end)[oFrlnSoldVal]
	--Scan-only data...
	,sum(case when PrCat = 'scan' and abs(SldTy) > 1 then pr.Qty else 0 end)[oScanSoldQty]
	,sum(case when PrCat = 'scan' and abs(SldTy) > 1 then pr.Cost else 0 end)[oScanSoldCost]
	,sum(case when PrCat = 'scan' and abs(SldTy) > 1 then pr.Val else 0 end)[oScanSoldVal]

	-- Bookworm Sales Only...
	--Distribution-only product.....
	,sum(case when PrCat in ('dist','scan') and SldTy = 0 then pr.Cost else 0 end)[bwDistSoldCost]
	,sum(case when PrCat in ('dist','scan') and SldTy = 0 then pr.Val else 0 end)[bwDistSoldVal]
	--Frontline-only product....
	,sum(case when PrCat = 'frln' and SldTy = 0 then pr.Cost else 0 end)[bwFrlnSoldCost]
	,sum(case when PrCat = 'frln' and SldTy = 0 then pr.Val else 0 end)[bwFrlnSoldVal]
	--Scan-only data...
	,sum(case when PrCat = 'scan' and SldTy = 0 then pr.Qty else 0 end)[bwScanSoldQty]
	,sum(case when PrCat = 'scan' and SldTy = 0 then pr.Cost else 0 end)[bwScanSoldCost]
	,sum(case when PrCat = 'scan' and SldTy = 0 then pr.Val else 0 end)[bwScanSoldVal]
from #Sales_prep pr 
group by BusinessMonth
	,LocationNo



--Collect RFI & Outbound Store to Store Xfers Data--------------------------
----------------------------------------------------------------------------
insert into #Xfers_prep
select 
    datefromparts(year(xh.CreateTime),month(xh.CreateTime),1)[BusinessMonth]
	,xh.LocationNo
	,TransferType[XfrTy]
	,pc.PTypeCategory[PrCat]
	,sum(xd.Quantity)[Qty]
	,sum(xd.DipsCost)[Cost]
from ReportsData..SipsTransferBinHeader xh 
    inner join ReportsData..SipsTransferBinDetail xd on xh.TransferBinNo = xd.TransferBinNo 
    inner join ReportsData..ProductMaster pm on xd.DipsItemCode = pm.ItemCode 
	inner join ReportsView..RDA_NewGoodsCosts_PTypeCategory pc on pm.ProductType = pc.ProductType 
where xh.StatusCode = 3
	and xd.StatusCode = 1
	and TransferType in (1,2,3,7)
	and xh.CreateTime >= @StartDate
	and xh.CreateTime < @EndDate
	and pc.PTypeClass = 'NEW'
	and pc.PTypeCategory <> 'gc'
group by 
    datefromparts(year(xh.CreateTime),month(xh.CreateTime),1)
	,xh.LocationNo
	,TransferType
	,pc.PTypeCategory

--Collect Inbound Store to Store Xfer Data--------------------------
--------------------------------------------------------------------
insert into #Xfers_prep
select 
    datefromparts(year(xh.CreateTime),month(xh.CreateTime),1)[BusinessMonth]
	,xh.ToLocationNo
	,-TransferType[XfrTy]
	,pc.PTypeCategory[PrCat]
	,sum(xd.Quantity)[Qty]
	,sum(xd.DipsCost)[Cost]
from ReportsData..SipsTransferBinHeader xh  
    inner join ReportsData..SipsTransferBinDetail xd on xh.TransferBinNo = xd.TransferBinNo 
    inner join ReportsData..ProductMaster pm on xd.DipsItemCode = pm.ItemCode 
	inner join ReportsView..RDA_NewGoodsCosts_PTypeCategory pc on pm.ProductType = pc.ProductType 
where xh.StatusCode = 3
	and xd.StatusCode = 1
	and TransferType = 3
	and xh.CreateTime >= @StartDate
	and xh.CreateTime < @EndDate
	and pc.PTypeClass = 'NEW'
	and pc.PTypeCategory <> 'gc'
group by 
    datefromparts(year(xh.CreateTime),month(xh.CreateTime),1)
	,xh.ToLocationNo
	,-TransferType
	,pc.PTypeCategory


-- Combine all Xfers data--------------------------------------
---------------------------------------------------------------
insert into #Xfers
select BusinessMonth
	,LocationNo
	,sum(case when XfrTy = 1 and PrCat = 'dist' then pr.Qty else 0 end)[DistTshQty]
	,sum(case when XfrTy = 1 and PrCat = 'dist' then pr.Cost else 0 end)[DistTshCost]
	,sum(case when XfrTy = 7 and PrCat = 'dist' then pr.Qty else 0 end)[DistDmgQty]
	,sum(case when XfrTy = 7 and PrCat = 'dist' then pr.Cost else 0 end)[DistDmgCost]
	,sum(case when XfrTy = 2 and PrCat = 'dist' then pr.Qty else 0 end)[DistDntQty]
	,sum(case when XfrTy = 2 and PrCat = 'dist' then pr.Cost else 0 end)[DistDntCost]
	,sum(case when XfrTy in (1,2,7) and PrCat = 'dist' then pr.Qty else 0 end)[TotDistRfiQty]
	,sum(case when XfrTy in (1,2,7) and PrCat = 'dist' then pr.Cost else 0 end)[TotDistRfiCost]
	,sum(case when XfrTy = 3 and PrCat = 'dist' then pr.Qty else 0 end)[DistOStSQty]
	,sum(case when XfrTy = 3 and PrCat = 'dist' then pr.Cost else 0 end)[DistOStSCost]
	,sum(case when XfrTy = -3 and PrCat = 'dist' then pr.Qty else 0 end)[DistIStSQty]
	,sum(case when XfrTy = -3 and PrCat = 'dist' then pr.Cost else 0 end)[DistIStSCost]

	,sum(case when XfrTy = 1 and PrCat = 'frln' then pr.Qty else 0 end)[FrlnTshQty]
	,sum(case when XfrTy = 1 and PrCat = 'frln' then pr.Cost else 0 end)[FrlnTshCost]
	,sum(case when XfrTy = 7 and PrCat = 'frln' then pr.Qty else 0 end)[FrlnDmgQty]
	,sum(case when XfrTy = 7 and PrCat = 'frln' then pr.Cost else 0 end)[FrlnDmgCost]
	,sum(case when XfrTy = 2 and PrCat = 'frln' then pr.Qty else 0 end)[FrlnDntQty]
	,sum(case when XfrTy = 2 and PrCat = 'frln' then pr.Cost else 0 end)[FrlnDntCost]
	,sum(case when XfrTy in (1,2,7) and PrCat = 'frln' then pr.Qty else 0 end)[TotFrlnRfiQty]
	,sum(case when XfrTy in (1,2,7) and PrCat = 'frln' then pr.Cost else 0 end)[TotFrlnRfiCost]
	,sum(case when XfrTy = 3 and PrCat = 'frln' then pr.Qty else 0 end)[FrlnOStSQty]
	,sum(case when XfrTy = 3 and PrCat = 'frln' then pr.Cost else 0 end)[FrlnOStSCost]
	,sum(case when XfrTy = -3 and PrCat = 'frln' then pr.Qty else 0 end)[FrlnIStSQty]
	,sum(case when XfrTy = -3 and PrCat = 'frln' then pr.Cost else 0 end)[FrlnIStSCost]
from #Xfers_prep pr
group by BusinessMonth
	,LocationNo



--Updating Tables----------------------------------------------
---------------------------------------------------------------

;with Mos as(
	select distinct BusinessMonth from #Sales
	union select distinct BusinessMonth from #Xfers
)
, Locs as(
	select distinct LocationNo from #Sales
	union select distinct LocationNo from #Xfers
)
insert into #KeyTable
select m.BusinessMonth
	,l.LocationNo
from Locs l cross join Mos m 


----Transaction 1---------------------------------------------------
--Remove any existing records from RDA_RU_NewGoodsCosts-------------[
------------------------------------------------------------------[
BEGIN TRY
	begin transaction

	delete ru   -- select count(*)
	from ReportsView..RDA_RU_NewGoodsCosts ru
		inner join #KeyTable kt on ru.BusinessMonth = kt.BusinessMonth and ru.LocationNo = kt.LocationNo;
			
	commit transaction
END TRY

BEGIN CATCH
	if @@trancount > 0 rollback transaction
	declare @msg1 nvarchar(2048) = error_message()  
	raiserror (@msg1, 16, 1)
END CATCH
---------------------------------------------------]
----------------------------------------------------]



----Transaction 2----------------------------------------------
--Adds new/updated records to RDA_RU_NewGoodsCosts-------------[
-------------------------------------------------------------[
BEGIN TRY
	begin transaction

	insert into ReportsView..RDA_RU_NewGoodsCosts
	select 
		kt.BusinessMonth
		,kt.LocationNo
		,isnull(sa.sDistSoldCost,0)[DistSoldCost]
		,isnull(sa.sDistSoldVal,0)[DistSoldVal]
		,isnull(sa.sFrlnSoldCost,0)[FrlnSoldCost]
		,isnull(sa.sFrlnSoldVal,0)[FrlnSoldVal]
		,isnull(sa.sScanSoldQty,0)[ScanSoldQty]
		,isnull(sa.sScanSoldCost,0)[ScanSoldCost]
		,isnull(sa.sScanSoldVal,0)[ScanSoldVal]
		,isnull(xr.DistTshQty,0)[DistTshQty]
		,isnull(xr.DistTshCost,0)[DistTshCost]
		,isnull(xr.DistDmgQty,0)[DistDmgQty]
		,isnull(xr.DistDmgCost,0)[DistDmgCost]
		,isnull(xr.DistDntQty,0)[DistDntQty]
		,isnull(xr.DistDntCost,0)[DistDntCost]
		,isnull(xr.TotDistRfiQty,0)[TotDistRfiQty]
		,isnull(xr.TotDistRfiCost,0)[TotDistRfiCost]
		
		-- Online Sales...
		,isnull(sa.oDistSoldCost,0)[DistOnlineSoldCost]
		,isnull(sa.oDistSoldVal,0) [DistOnlineSoldVal]
		,isnull(sa.oFrlnSoldCost,0)[FrlnOnlineSoldCost]
		,isnull(sa.oFrlnSoldVal,0) [FrlnOnlineSoldVal]
		
		-- Bookworm Sales...
		,isnull(sa.bwDistSoldCost,0)[DistBookwormSoldCost]
		,isnull(sa.bwDistSoldVal,0) [DistBookwormSoldVal]
		,isnull(sa.bwFrlnSoldCost,0)[FrlnBookwormSoldCost]
		,isnull(sa.bwFrlnSoldVal,0) [FrlnBookwormSoldVal]
		
		-- Frontline Xfers...
		,isnull(xr.FrlnTshQty,0)[FrlnTshQty]
		,isnull(xr.FrlnTshCost,0)[FrlnTshCost]
		,isnull(xr.FrlnDmgQty,0)[FrlnDmgQty]
		,isnull(xr.FrlnDmgCost,0)[FrlnDmgCost]
		,isnull(xr.FrlnDntQty,0)[FrlnDntQty]
		,isnull(xr.FrlnDntCost,0)[FrlnDntCost]
		,isnull(xr.TotFrlnRfiQty,0)[TotFrlnRfiQty]
		,isnull(xr.TotFrlnRfiCost,0)[TotFrlnRfiCost]

		-- Dist & Frln Location Xfers
		,isnull(xr.DistOStSQty,0) [DistLocXfrOutQty]
		,isnull(xr.DistOStSCost,0)[DistLocXfrOutCost]
		,isnull(xr.DistIStSQty,0) [DistLocXfrInQty]
		,isnull(xr.DistIStSCost,0)[DistLocXfrInCost]
		,isnull(xr.FrlnOStSQty,0) [FrlnLocXfrOutQty]
		,isnull(xr.FrlnOStSCost,0)[FrlnLocXfrOutCost]
		,isnull(xr.FrlnIStSQty,0) [FrlnLocXfrInQty]
		,isnull(xr.FrlnIStSCost,0)[FrlnLocXfrInCost]
		
	from #KeyTable kt
		left join #Sales sa on sa.BusinessMonth = kt.BusinessMonth and sa.LocationNo = kt.LocationNo
		left join #Xfers xr on xr.BusinessMonth = kt.BusinessMonth and xr.LocationNo = kt.LocationNo
	order by 1,2;

	commit transaction
END TRY

BEGIN CATCH
	if @@trancount > 0 rollback transaction
	declare @msg2 nvarchar(2048) = error_message()  
	raiserror (@msg2, 16, 1)
END CATCH
---------------------------------------------------]
----------------------------------------------------]



--Temp File Cleanup--------------
---------------------------------
drop table if exists #Sales_prep
drop table if exists #Xfers_prep
drop table if exists #Sales
drop table if exists #Xfers
drop table if exists #KeyTable

END