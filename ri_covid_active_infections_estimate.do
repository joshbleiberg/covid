preserve
//Pulls Data from Rhode Island Google Drive
	*https://ri-department-of-health-covid-19-data-rihealth.hub.arcgis.com/
	*https://docs.google.com/spreadsheets/d/1c2QrNMz8pIbYEKzMJL7Uh2dtThOJa2j1sSMwiDo5Gz4/edit#gid=264100583
local key 1c2QrNMz8pIbYEKzMJL7Uh2dtThOJa2j1sSMwiDo5Gz4
local id 1592746937
tempfile sheetsFile

copy "https://docs.google.com/spreadsheets/d/`key'/export?gid=`id'&format=xlsx" `sheetsFile', replace
import excel `sheetsFile', clear firstrow

//Creating Percent Positive Rate
gen positive_rate=Dailynumberofpositivetests/Dailytotaltestscompletedmay
gen time=_n
drop if inrange(time,1,6)
drop time
gen time=_n
//Creating Lagged (14 Days) Percent Positive Rate
gen pos_lag_14=.
gen test_lag_14=.
levelsof time
local times=r(levels)
foreach i of local times{
	local first_14=`i'-14
	qui sum Dailynumberofpositivetests if inrange(time,`first_14',`i')
	qui replace pos_lag_14=r(sum) if time==`i'
	qui sum Dailytotaltestscompletedmay if inrange(time,`first_14',`i')
	qui replace test_lag_14=r(sum) if time==`i'
}
gen pos_rate_lag=pos_lag_14/test_lag_14

//Generating Variables to Estimate Pseudo R-Naught and Active Infection Rate
gen active_10_day=.
gen active_today=.
gen test_last_14d=.

levelsof time
local times=r(levels)
foreach i of local times{
	local day_min_20=`i'-20
	local day_min_14=`i'-14
	local day_min_10=`i'-10
	
	qui sum Dailynumberofpositivetests if inrange(time,`day_min_20',`day_min_10')
	qui replace active_10_day=r(sum) if _n==`i'

	qui sum Dailynumberofpositivetests if inrange(time,`day_min_14',`i')
	qui replace active_today=r(sum) if _n==`i'
	
	qui sum Dailytotaltestscompletedmay if inrange(time,`day_min_14',`i')
	qui replace test_last_14d=r(sum) if _n==`i'
}

//Cumulative Number of People who had 2 vaccine shots 2 weeks ago
destring AH Dailynumberoffirstvaccinedo Dailynumberofsecondvaccined, force replace
gen vacc_adj_14d=AH[_n-14]
//Psuedo R Naught: Active Infections Today/Active Infections 10 days ago
gen psuedo_r_0=active_today/active_10_day
//Number of tests in the last 14 days minus 10 percent to account for possible double tests
replace vacc_adj_14d=0 if vacc_adj_14d==.
gen percent_test_d14=((test_last_14d-(test_last_14d*.1))/(1059000-vacc_adj_14d))
//Estimated Infections: The inverse of the percent of the population in the last 14 days
gen active_rate_adjuster=1/percent_test_d14
//Implied Active Infection Rate After Subtracting Vaccinated
gen active_rate_adjusted=((active_today*active_rate_adjuster))/(1059000)
	qui sum active_rate_adjusted
	gen active_rate_adjusted_ul=active_rate_adjusted+r(sd)
	gen active_rate_adjusted_ll=active_rate_adjusted-r(sd)
	replace active_rate_adjusted_ll=0 if inrange(active_rate_adjusted_ll,-10000000,0) //Infect rate can't be negative
//Recent Stats
qui sum time
local recent=r(max)-14
list Date  pos_rate_lag  active_rate_adjusted vacc_adj_14d  if inrange(time,`recent',r(max))

local today=r(max)
local tomorrow=`today'+1
local two_weeks=`today'+14 

//Forecast of Active Infections- Quick and Dirty Model
qui reg active_rate_adjusted time psuedo_r_0 vacc_adj_14d if inrange(time,`day_min_14',`today')
qui margin, at(time=(`tomorrow'(1)`two_weeks'))
mat predict_mat=r(table)'

expand 15 in 1
replace time=_n

gen predict_bet=0
gen predict_lci=0
gen predict_uci=0

qui sum predict_bet if inrange(time,`tomorrow',`two_weeks')
local predict_sd=r(sd)

levelsof time if inrange(time,`tomorrow',`two_weeks')
local times=r(levels)
local rows=1
foreach i of local times{
replace predict_bet=predict_mat[`rows',1] if time==`i'
replace predict_lci=predict_mat[`rows',5] if time==`i'
replace predict_uci=predict_mat[`rows',6] if time==`i'
	
local rows=`rows'+1
}

//Display Recent Stats
qui sum time
local start=r(max)-28
local stop=r(max)-14

rename Dailynumberofpositivetests pos_tests
rename Dailytotaltestscompletedmay tests
rename Dailynumberoffirstvaccinedo first_vac
rename Dailynumberofsecondvaccined second_vac
//Creating Percent of Population with at least one shot
gen first_shot_pct=first_vac/1059000
list Date pos_tests tests positive_rate pos_rate_lag active_rate_adjusted first_vac second_vac first_shot_pct if inrange(time,`start',`stop')

di "Date pos_tests tests positive_rate pos_rate_lag active_rate_adjusted first_vac second_vac first_shot_pct"

replace active_rate_adjusted_ll=. if inrange(time,`tomorrow',`two_weeks')
replace active_rate_adjusted_ul=. if inrange(time,`tomorrow',`two_weeks')
replace active_rate_adjusted=. if inrange(time,`tomorrow',`two_weeks')
//Rhode Island Active Covid Infections Estimate in Rhode Island
graph twoway (rarea active_rate_adjusted_ll active_rate_adjusted_ul time, color(gs10)) ///
	|| (line active_rate_adjusted time, lcolor(blue)) ///
	|| (line predict_bet time if inrange(time,`tomorrow',`two_weeks'), lcolor(red)), ///
	title("Estimated Active Covid-19 Infection Rate in Rhode Island", color(black)) ///
	xtitle("Date") ///
	xlabel(1 "March" 60 "May" 121 "July" 183 "September" 244 "November" 305 "January" 363 "March" `today' "Today", labc(black)) ///
	ytitle("Percent", size(small)) ///
	ylabel( 0 "0%" .01 "1%" .02 "2%" .03 "3%" .04 "4%" .05 "5%" .06 "6%" ///
	.07 "7%" .08 "8%" .09 "9%" .10 "10%" .11 "11%" .12 "12%" .13 "13%" .14 "14%" ///
	.15 "15%" .16 "16%" .17 "17%" .18 "18%" .19 "19%" .20 "20%" .21 "21%" .22 "22%" ///
	.23 "23%" .24 "24%" .25 "25%" , labc(black) labsize(vsmall) angle(0) nogrid) ///
	yline(0 .05 .10 .15 .20 .25, lp(solid) lc(black)) ///
	scheme(blue) ///
	xlabel(, angle(45)) ///
	legend(off) graphregion(color(white)) bgcolor(white) plotregion(margin(none))
restore
