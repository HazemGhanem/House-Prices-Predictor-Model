/* ------------------------------------------------- */
/*                STEP 1: Import Data                */
/* ------------------------------------------------- */

proc import datafile="/home/u63530524/sasuser.v94/BD Project/Egypt_Houses_Price.csv"
    out=houses
    dbms=csv
    replace;
    getnames=yes;
run;

title "Dataset Overview";
proc contents data=houses; 
run;



/* ------------------------------------------------- */
/*        STEP 2: Data Cleaning - Missing Values     */
/* ------------------------------------------------- */

title "Cleaning Data - Handling Missing Values and 'Unknown' Labels";
data houses;
    set houses;

    /* Remove rows with missing values or 'Unknown' in key columns */
    if missing(Price) or missing(Bedrooms) or missing(Bathrooms) or missing(Area) 
       or City = " " or Compound = " " 
    then delete;
run;



/* ------------------------------------------------- */
/*        STEP 3: Remove Outliers Using IQR          */
/* ------------------------------------------------- */

title "Removing Outliers in 'Area' Using IQR";
proc univariate data=houses noprint;
    var Area;
    output out=iqr_out pctlpts=25, 75 pctlpre=Q_;
run;

data houses;
    if _N_ = 1 then set iqr_out; /* Merge IQR values into the dataset */
    set houses;
    iqr = Q_75 - Q_25;
    /* Remove outliers based on Area */
    if Area < Q_25 - 1.5 * iqr or Area > Q_75 + 1.5 * iqr then delete;
    drop Q_: iqr; /* Drop unnecessary IQR-related variables */
run;


/* ------------------------------------------------- */
/*           STEP 4: One-Hot Encoding        	     */
/* ------------------------------------------------- */

title "Performing One-Hot Encoding Silently";

/* Step 4a: Generate dummy variables */
proc glmmod data=houses outdesign=houses_encoded(drop=Intercept) noprint;
    class City Compound Furnished Payment_Option;
    model Price = City Compound Furnished Payment_Option;
run;

/* Step 4b: Merge dummy variables back into the main table */
data houses;
    merge houses houses_encoded;
    drop Intercept; /* Drop intercept to keep the dataset clean */
run;



/* ------------------------------------------------- */
/*      STEP 5: Scale and Normalize Numerical Data   */
/* ------------------------------------------------- */

title "Scaling and Normalizing Numerical Features";
proc standard data=houses mean=0 std=1 out=houses;
    var Bedrooms Bathrooms Area; /* Normalize numerical variables */
run;


/* ------------------------------------------------- */
/*      STEP 6: Split Data into Train and Test       */
/* ------------------------------------------------- */

title "Splitting Data into Training and Testing Sets";
proc surveyselect data=houses out=houses seed=12345 samprate=0.8 outall;
run;

data houses;
    set houses;
    if selected = 1 then Train_Flag = 1; else Train_Flag = 0;
    drop selected; /* Drop intermediate variable */
run;


/* ------------------------------------------------- */
/*   STEP 7: Regression Model - Predict House Price  */
/* ------------------------------------------------- */

title "Regression Model: Predicting House Prices";
ods graphics on; /* Enable ODS graphics for visualization */

proc reg data=houses(where=(Train_Flag=1)) plots=all;
    model Price = Bedrooms Bathrooms Area City_: Compound_: Furnished_: Payment_Option_: / vif collin;
    output out=houses p=predicted_price r=residual;
run;

ods graphics off; /* Disable ODS graphics after the regression step */



/* ---------------------------------------------------- */
/* STEP 8: Visualize Residuals and Predicted vs Actual  */
/* -----------------------------------------------------*/

/* Scatter Plot: Predicted Prices vs Residuals */
title "Residual Plot - Predicted vs Residuals";
proc sgplot data=houses;
    scatter x=predicted_price y=residual / markerattrs=(symbol=CircleFilled color=blue);
    refline 0 / axis=y lineattrs=(pattern=solid color=red);
    xaxis label="Predicted Prices";
    yaxis label="Residuals";
    title "Residuals vs Predicted Prices";
run;


/* Scatter Plot: Actual Prices vs Predicted Prices */
title "Actual vs Predicted Prices";
proc sgplot data=houses;
    scatter x=Price y=predicted_price / markerattrs=(symbol=CircleFilled color=green);
    lineparm x=0 y=0 slope=1 / lineattrs=(pattern=solid color=red);
    xaxis label="Actual Prices";
    yaxis label="Predicted Prices";
    title "Actual vs Predicted Prices with Perfect Fit Line";
run;



title "Feature Coefficients Visualization";
/* Extract Coefficients from the regression model */
proc reg data=houses(where=(Train_Flag=1)) outest=coefficients;
    model Price = Bedrooms Bathrooms Area City_: Compound_: Furnished_: Payment_Option_:;
run;

/* Visualize the Regression Coefficients */
data coefficients_cleaned;
    set coefficients;
    /* Reshape the coefficients dataset to include feature names and coefficient values */
    length Feature $50;
    array _all_ _numeric_;
    do i = 1 to dim(_all_);
        if vvaluex(vvaluex(_all_[i])) ne . then do;
            Feature = vvaluex(vvaluex(_all_[i]));
            Estimate = _all_[i];
            output;
        end;
    end;
    drop i;
run;


/* Coefficients Visualization */
proc sgplot data=coefficients_cleaned;
    vbar Feature / response=Estimate datalabel barwidth=0.6 fillattrs=(color=blue);
    xaxis label="Features";
    yaxis label="Coefficient Estimates";
    title "Feature Importance - Regression Coefficients";
run;






/* ------------------------------------------------- */
/*   STEP 9: Evaluate Regression Model Performance   */
/* ------------------------------------------------- */

title "Model Performance Metrics";
data houses;
    set houses;
    if Train_Flag = 1 then residual_sq = residual**2; /* Residual for training set */
run;


proc means data=houses(where=(Train_Flag=1)) mean stddev;
    var residual_sq;
    title "Root Mean Square Error (RMSE)";
run;

proc corr data=houses(where=(Train_Flag=1));
    var Price predicted_price;
    title "R-Squared: Correlation Between Actual and Predicted Prices";
run;


/* ------------------------------------------------- */
/*     STEP 10: Logistic Model - Predict Compound    */
/* ------------------------------------------------- */

title "Logistic Regression: Predicting Compound";
proc logistic data=houses(where=(Train_Flag=1));
    model Compound_1(event='1') = Bedrooms Bathrooms Area City_: Furnished_: Payment_Option_:;
    output out=houses p=predicted_compound;
run;


/* ------------------------------------------------- */
/*     STEP 11: Export Final Processed Table         */
/* ------------------------------------------------- */

title "Exporting Final Processed Table";
proc export data=houses
    outfile="/home/u63530524/final_processed_houses.xlsx"
    dbms=xlsx
    replace;
run;

title "Data Exported Successfully";
