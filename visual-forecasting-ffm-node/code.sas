ods output OutInfo = _outInformation;

proc tsmodel data=&vf_libIn.."&vf_inData"n lead = &vf_lead.
            outobj=(outfor  = &vf_libOut.."&vf_outFor"n
            outSelect = &vf_libOut.."&vf_outSelect"n
            outStat = &vf_libOut.."&vf_outStat"n
            outmodelinfo = &vf_libOut.."&vf_outModelInfo"n
            outvarstatus=&vf_libOut..outvarstatus
            pylog=&vf_libOut..pylog)
            outarray = &vf_libOut..outarray
            outlog = &vf_libOut.."&vf_outLog"n;
    id &vf_timeID interval = &vf_timeIDInterval setmissing = &vf_setMissing trimid = LEFT;
    %vf_varsTSMODEL;

    *define the by variables if exist;
    %if "&vf_byVars" ne "" %then %do;
       by &vf_byVars;
    %end;
    
    outarray ffm_fcst;
    require atsm tsm extlang;
    submit;
    
    /* some TensorFlow Keras model options */

    CHRONOS_ENDPOINT = "&_CHRONOS_ENDPOINT";      /* endpoint of the chronos model      */
    PREDICTION_LENGTH = &_PREDICTION_LENGTH.;   /* maximum number of epochs           */
    NUM_SAMPLES = &_NUM_SAMPLES.;               /* learning rate for optimizer        */
    TEMPERATURE = &_TEMPERATURE.;               /* minibatch size                     */
    TOP_K = &_TOP_K.;                           /* seed for random number             */ 
    TOP_P = &_TOP_P.;                           /* early stopping delta parameter     */
    
    declare object py(PYTHON3); 
    rc = py.Initialize();
    rc = py.AddVariable(&vf_depVar,'ALIAS','y') ;
    rc = py.AddVariable(&vf_timeID, 'ALIAS', 'ds');
    rc = py.AddVariable(CHRONOS_ENDPOINT);
    rc = py.AddVariable(PREDICTION_LENGTH);
    rc = py.AddVariable(_LEAD_); /*pass the predefined variable to TF*/ 
    rc = py.AddVariable(PREDICTION_LENGTH);
    rc = py.AddVariable(NUM_SAMPLES);
    rc = py.AddVariable(TEMPERATURE);
    rc = py.AddVariable(TOP_K);
    rc = py.AddVariable(TOP_P);
    rc = py.AddVariable(ffm_fcst,"READONLY","NO","ARRAYRESIZE","YES","ALIAS",'PREDICT'); 
     * rc = py.AddEnvVariable('_TKMBPY_DEBUG_FILES_PATH', &log_folder);

    rc = py.pushCodeLine('import requests');
    rc = py.pushCodeLine('import json');
    rc = py.pushCodeLine('import numpy as np');
    rc = py.pushCodeLine('url = CHRONOS_ENDPOINT');
    rc = py.pushCodeLine('prediction_lenth = int(PREDICTION_LENGTH)');
    rc = py.pushCodeLine('num_samples = int(NUM_SAMPLES)');
    rc = py.pushCodeLine('temperature = float(TEMPERATURE)');
    rc = py.pushCodeLine('top_k = int(TOP_K)');
    rc = py.pushCodeLine('top_p = float(TOP_P)');
    rc = py.pushCodeLine('y = TARGET[0:len(TARGET)-lead]');
    rc = py.pushCodeLine('payload = json.dumps({');
    rc = py.pushCodeLine(' "prediction_length": prediction_length,');
    rc = py.pushCodeLine(' "num_samples": num_samples,');
    rc = py.pushCodeLine(' "temperature": temperature,');
    rc = py.pushCodeLine(' "top_k": top_k',);
    rc = py.pushCodeLine(' "top_p": top_p',);
    rc = py.pushCodeLine(' "data": y');
    rc = py.pushCodeLine('})');
    rc = py.pushCodeLine('headers = {');
    rc = py.pushCodeLine(' "Content-Type": "application/json"');
    rc = py.pushCodeLine('}');
    rc = py.pushCodeLine('response = requests.request("POST", url, headers=headers, data=payload)');
    rc = py.pushCodeLine('forecast = response.text');
    rc = py.pushCodeLine('forecast_np_array = np.genfromtxt(forecast.splitlines(), delimiter=",", skip_header=1');
    rc = py.pushCodeLine('header = forecast.splitline()[0].split(",")');
    rc = py.pushCodeLine('forecast_series_median = forecast_array[:, header.index("median")]');
    rc = py.pushCodeLine('pred_time_series = np.concatenate((y, forecast_array_median))');
    rc = py.pushCodeLine('PREDICT = pred_time_series');
    rc = py.pushCodeLine('forecast_series_low = forecast_array[:, header.index("low")]');
    rc = py.pushCodeLine('forecast_series_high = forecast_array[:, header.index("high")]');
    rc = py.Run();  
    /* Store the execution and resource usage statistics logs */
    declare object pylog(OUTEXTLOG);
    rc = pylog.Collect(py,'EXECUTION');
    declare object outvarstatus(OUTEXTVARSTATUS);
    rc = outvarstatus.Collect(py);
    declare object pyExmSpec(EXMSPEC);
    rc = pyExmSpec.open();
    rc = pyExmSpec.setOption('METHOD','PERFECT');
    rc = pyExmSpec.setOption('NLAGPCT',0);
    rc = pyExmSpec.setOption('PREDICT','tf_fcst');
    rc = pyExmSpec.close();
    
    declare object dataFrame(tsdf);
    declare object diagnose(diagnose);
    declare object diagSpec(diagspec);
    declare object inselect(selspec); 
    declare object forecast(foreng);
    
    /*initialize the tsdf object and assign the time series roles: setup dependent and independent variables*/
    rc = dataFrame.initialize();
    rc = dataFrame.AddSeries(ffm_fcst);
    rc = dataFrame.addY(&vf_depVar);
    
    /*Run model selection and forecast*/                     
    rc = inselect.Open(1); 
    rc = inselect.AddFrom(pyExmSpec);
    rc = inselect.close(); 
    
    /*initialize the foreng object with the diagnose result and run model selecting and generate forecasts;*/         
    rc = forecast.initialize(dataFrame);
    rc = forecast.AddFrom(inselect);
    rc = forecast.setOption('lead', &vf_lead);
    rc = forecast.setOption('back', &vf_back);
    
    %if "&vf_allowNegativeForecasts" eq "FALSE" %then %do;
        rc = forecast.setOption('fcst.bd.lower',0);
    %end;
    rc = forecast.Run();

    /*collect forecast results*/
    declare object outFor(outFor);
    declare object outSelect(outSelect);
    declare object outStat(outStat);
    declare object outModelInfo(outModelInfo);

    /*collect the forecast and statistic-of-fit from the forgen object run results; */
    rc = outFor.collect(forecast);
    rc = outSelect.collect(forecast); 
    rc = outStat.collect(forecast);  
    rc = outModelInfo.collect(forecast);
endsubmit;
run;

/* generate outinformation CAS table */
data &vf_libOut.."&vf_outInformation"n;
    set work._outInformation;
run;