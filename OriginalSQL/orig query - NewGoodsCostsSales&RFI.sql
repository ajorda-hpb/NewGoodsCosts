--Product Costs for New Goods Sales & RFI Transfers------------
----Product costs for Distribution/Frontline/SCAN Sales 
----& Distribution Transfers removing product from inventory 
----(Damage/Donate/Trash) by Month & LocationNo
---------------------------------------------------------------
-- TODO 1. Add Costs for Store to Store Xfers, per Mary's email on 9/18/20. 
-- TODO 2. Ask Laura about iStore sales & possibly HPB.com & Ship to Store & Search 'n Ship, too. (see 4/17/19 email at 11:02)
---------------------------------------------------------------
-- 10/6/20: Added Store Xfers & Online Sales, but had to refactor since those are either
-- in different tables (online sales) or made the original query too wide/ridiculous (Xfers).
-- Data now goes into Tidy staging tables (these will probably become what's saved for the sumac report to pull against)
-- Before being rolled into the wide, report-formatted output.
---------------------------------------------------------------
-- 4/6/21: Added Bookworm Sales, informed by BookwormCart, which still has some issues:
-- sih sales show bookworm sames as itemcode 10222778, classed as USED & SPECIAL.
-- some sih sales show $0 for a valid order
-- sih sales' ExtAmt includes all taxes & ship fees associated with the order.
---------------------------------------------------------------
-- 4/23/21: Was missing online sale refunds by limiting SldTy to positive values...oops. >.> 
---------------------------------------------------------------
-- 7/6/2021: Added criteria to exclude HPB.com store pickup orders
-- c.f. email from Rebekah, HPB.com Orders and Store Pick Up Orders, on 6/28/2021 12:21 pm


--Report Inputs - date range in month increments---------------
---------------------------------------------------------------
declare @StartDate date  -- start date is INclusive
declare @EndDate date  -- end date is EXclusive
set @StartDate = '6/1/21'
set @EndDate = '7/1/21'


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


--Collect Brick & Mortar Sales Data-------------------------------------------
------------------------------------------------------------------------------
insert into #Sales_prep
select 
	datefromparts(datepart(YY,sih.BusinessDate),datepart(MM,sih.BusinessDate),1)[BusinessMonth]
	,loc.LocationNo
	,1[SldTy]
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end[PrCat]
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
	inner join ReportsData..ProductTypes pt on pm.ProductType = pt.ProductType 
where shh.Status = 'A'
	and shh.XactionType = 'S'
	and sih.BusinessDate >= @StartDate
	and sih.BusinessDate < @EndDate
	and pm.ProductType not in ('PGC ','EGC ')
	and pt.PTypeClass <> 'USED'
group by 
	datefromparts(datepart(YY,sih.BusinessDate),datepart(MM,sih.BusinessDate),1)
	,loc.LocationNo
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end



-- Collect iStore Online Sales Data----------------------------
---------------------------------------------------------------
-- Shipped data--------
insert into #Sales_prep
select datefromparts(datepart(YY,om.OrderDate),datepart(MM,om.OrderDate),1)[BusinessMonth]
    ,isnull(od.LocationNo,fa.HPBLocationNo)[LocationNo]
	,2[SldTy]
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end[PrCat]
	,sum(om.ShippedQuantity)[Qty]
	,sum(pm.Cost)[Cost]
	,sum(om.Price)[Val]
	,sum(om.ShippingFee)[Fee]
from isis..Order_Monsoon om 
	inner join isis..App_Facilities fa on om.FacilityID = fa.FacilityID
	--pre-2014ish, SAS & XFRs would show up in Monsoon, so specifying 'MON' excludes those
	left join ofs..Order_Header oh on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'MON' 
	--Grabs fulfilment location where available, otherwise uses originating location
	left join ofs..Order_Detail od on oh.OrderID = od.OrderID and od.Status in (1,4)
		--Problem orders have ProblemStatusID not null
		and (od.ProblemStatusID is null or od.ProblemStatusID = 0)	
	inner join ReportsData..ProductMaster pm on right(om.SKU,20) = pm.ItemCode
where om.ShippedQuantity > 0
	and om.OrderStatus in ('New','Pending','Shipped')
	and om.OrderDate < @EndDate 
	and om.OrderDate >= @StartDate 
	and left(om.SKU,1) = 'D'
group by datefromparts(datepart(YY,om.OrderDate),datepart(MM,om.OrderDate),1)
    ,isnull(od.LocationNo,fa.HPBLocationNo)
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end

-- Refunds data--------
insert into #Sales_prep
select datefromparts(datepart(YY,om.RefundDate),datepart(MM,om.RefundDate),1)[BusinessMonth]
    ,isnull(od.LocationNo,fa.HPBLocationNo)[LocationNo]
	,-2[SldTy]
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end[PrCat]
	--Think refunded product doesn't go back to the store per se... 
	,0[Qty] 
	,0[Cost]
	,-sum(om.RefundAmount)[Val]
	,0[Fee]
from isis..Order_Monsoon om 
	inner join isis..App_Facilities fa on om.FacilityID = fa.FacilityID
	--pre-2014ish, SAS & XFRs would show up in Monsoon, so this excludes those
	left join ofs..Order_Header oh on om.ISIS_OrderID = oh.ISISOrderID and oh.OrderSystem = 'MON' 
	--Grabs fulfilment location where available, otherwise uses originating location
	left join ofs..Order_Detail od on oh.OrderID = od.OrderID and od.Status in (1,4)
		--Problem orders have ProblemStatusID not null
		and (od.ProblemStatusID is null or od.ProblemStatusID = 0)	
	inner join ReportsData..ProductMaster pm on right(om.SKU,20) = pm.ItemCode
where om.OrderStatus in ('New','Pending','Shipped')
	and om.RefundAmount > 0
	and om.RefundDate < @EndDate 
	and om.RefundDate >= @StartDate
	and left(om.SKU,1) = 'D'
group by datefromparts(datepart(YY,om.RefundDate),datepart(MM,om.RefundDate),1)
    ,isnull(od.LocationNo,fa.HPBLocationNo)
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end


-- Collect HPB.com Online Sales Data---------------------------
---------------------------------------------------------------
-- Shipped data--------
insert into #Sales_prep
select 
	datefromparts(datepart(YY,om.OrderDate),datepart(MM,om.OrderDate),1)[BusinessMonth]
	,fa.HPBLocationNo[LocationNo]
	,3[SldTy]
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end[PrCat]
	,sum(om.Quantity)[Qty]
	,sum(pm.Cost)[Cost]
	,sum(om.ExtendedAmount)[Val]
	,sum(om.ShippingAmount)[Fee]
from isis..Order_Omni om 
	inner join isis..App_Facilities fa on om.FacilityID = fa.FacilityID
	inner join ReportsData..ProductMaster pm on right(om.SKU,20) = pm.ItemCode
    inner join ReportsView..ProdGoals_ItemMaster it on pm.ItemCode = it.ItemCode
where om.OrderStatus not in ('canceled')
	and om.ItemStatus = 'shipped'
    and om.ShippingMethod <> '222'
	and om.OrderDate < @EndDate 
	and om.OrderDate >= @StartDate 
	and left(om.SKU,1) = 'D'
	and om.Quantity > 0
group by datefromparts(datepart(YY,om.OrderDate),datepart(MM,om.OrderDate),1)
	,fa.HPBLocationNo
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end

-- Refunds data--------
insert into #Sales_prep
select 
	datefromparts(datepart(YY,om.SiteLastModifiedDate),datepart(MM,om.SiteLastModifiedDate),1)[BusinessMonth]
    ,fa.HPBLocationNo[LocationNo]
	,-3[SldTy]
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end[PrCat]
	--Same idea... don't think we actually get the thing back to the store.
	,0[Qty] 
	,0[Cost]
	,-sum(om.ItemRefundAmount)[Val]
	,0[Fee]
from isis..Order_Omni om 
	inner join isis..App_Facilities fa on om.FacilityID = fa.FacilityID
	inner join ReportsData..ProductMaster pm on right(om.SKU,20) = pm.ItemCode
where om.OrderStatus not in ('canceled')
	and om.ItemStatus = 'shipped'
    and om.ShippingMethod <> '222'
	and om.SiteLastModifiedDate < @EndDate 
	and om.SiteLastModifiedDate >= @StartDate 								  
	and left(om.SKU,1) = 'D'
	and om.Quantity > 0
	and om.ItemRefundAmount > 0
group by 
	datefromparts(datepart(YY,om.SiteLastModifiedDate),datepart(MM,om.SiteLastModifiedDate),1)
    ,fa.HPBLocationNo
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end



--Collect Brick & Mortar Bookworm REGISTER Data-------------------------------
------------------------------------------------------------------------------
insert into #Sales_prep
select 
	cast(dateadd(MM,datediff(MM,0,sih.BusinessDate),0) as date)[BusinessMonth]
    ,bw.LocationNo
	,0[SldTy]
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end[PrCat]
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
	inner join ReportsData..ProductTypes pt on pm.ProductType = pt.ProductType 
where shh.Status = 'A'
    and shh.XactionType = 'S'
	and sih.BusinessDate >= @StartDate
	and sih.BusinessDate < @EndDate
	and pm.ProductType not in ('PGC ','EGC ')
	and pt.PTypeClass <> 'USED'
	and sih.ItemCode = '00000000000010222778' 
group by 
	cast(dateadd(MM,datediff(MM,0,sih.BusinessDate),0) as date)
    ,bw.LocationNo
	,case when pm.ProductType = 'SCAN' then 'scan' when right(rtrim(pm.ProductType),1) <> 'F' then 'dist' else 'frln' end




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
	datefromparts(datepart(YY,xh.CreateTime),datepart(MM,xh.CreateTime),1)[BusinessMonth]
	,xh.LocationNo
	,TransferType[XfrTy]
	,case when pm.ProductType not like '%F' then 'dist' else 'frln' end[PrCat]
	,sum(xd.Quantity)[Qty]
	,sum(xd.DipsCost)[Cost]
from ReportsData..SipsTransferBinHeader xh
    inner join ReportsData..SipsTransferBinDetail xd on xh.TransferBinNo = xd.TransferBinNo 
    inner join ReportsData..ProductMaster pm on xd.DipsItemCode = pm.ItemCode 
	inner join ReportsData..ProductTypes pt on pm.ProductType = pt.ProductType 
where xh.StatusCode = 3
	and xd.StatusCode = 1
	and TransferType in (1,2,3,7)
	and xh.CreateTime >= @StartDate
	and xh.CreateTime < @EndDate
	-- and pm.ProductType not like '%F'
	and pm.ProductType not in ('PGC ','EGC ') 
	and pt.PTypeClass <> 'USED'
group by 
	datefromparts(datepart(YY,xh.CreateTime),datepart(MM,xh.CreateTime),1)
	,xh.LocationNo
	,TransferType
	,case when pm.ProductType not like '%F' then 'dist' else 'frln' end

--Collect Inbound Store to Store Xfer Data--------------------------
--------------------------------------------------------------------
insert into #Xfers_prep
select 
	datefromparts(datepart(YY,xh.CreateTime),datepart(MM,xh.CreateTime),1)[BusinessMonth]
	,xh.ToLocationNo
	,-TransferType[XfrTy]
	,case when pm.ProductType not like '%F' then 'dist' else 'frln' end[PrCat]
	,sum(xd.Quantity)[Qty]
	,sum(xd.DipsCost)[Cost]
from ReportsData..SipsTransferBinHeader xh 
    inner join ReportsData..SipsTransferBinDetail xd on xh.TransferBinNo = xd.TransferBinNo 
    inner join ReportsData..ProductMaster pm on xd.DipsItemCode = pm.ItemCode 
	inner join ReportsData..ProductTypes pt on pm.ProductType = pt.ProductType 
where xh.StatusCode = 3
	and xd.StatusCode = 1
	and TransferType = 3
	and xh.CreateTime >= @StartDate
	and xh.CreateTime < @EndDate
	-- and pm.ProductType not like '%F'
	and pm.ProductType not in ('PGC ','EGC ') 
	and pt.PTypeClass <> 'USED'
group by 
	datefromparts(datepart(YY,xh.CreateTime),datepart(MM,xh.CreateTime),1)
	,xh.ToLocationNo
	,-TransferType
	,case when pm.ProductType not like '%F' then 'dist' else 'frln' end


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



--Report Output------------------------------------------------
---------------------------------------------------------------

;with Mos as(
	select distinct BusinessMonth from #Sales
	union select distinct BusinessMonth from #Xfers
)
, Locs as(
	select distinct LocationNo from #Sales
	union select distinct LocationNo from #Xfers
)
-- insert into ReportsView.dbo.RDA_RU_NewGoodsCosts
select m.BusinessMonth
	,l.LocationNo
	-- Original Data output, plus StS Xfers at the end...
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
	
from Locs l cross join Mos m 
	left join #Sales sa on sa.BusinessMonth = m.BusinessMonth and sa.LocationNo = l.LocationNo
	left join #Xfers xr on xr.BusinessMonth = m.BusinessMonth and xr.LocationNo = l.LocationNo
order by m.BusinessMonth
	,l.LocationNo


--Temp File Cleanup--------------------------------------------
---------------------------------------------------------------
/*
drop table if exists #Sales_prep
drop table if exists #Xfers_prep
drop table if exists #Sales
drop table if exists #Xfers
*/




