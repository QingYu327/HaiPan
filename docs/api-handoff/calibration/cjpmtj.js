jQuery(function($){
	$("#btn_group_div").show();
	//表单验证
	$("#ajaxForm").validateForm({
		beforeSubmit		:function(formData,jqForm,options){return false;}
	});
	//起始学年学期改变时影响终止学年学期
	$("#qsXnxq").change(function() {
		var qsxnxq = $("#qsXnxq").val();
		$("#zzXnxq option").each(function() {
			$(this).show();
			$('#zzXnxq').trigger("chosen:updated");
		});
		var zzxnxq = $("#zzXnxq").val();
		if (qsxnxq > zzxnxq) {
			$("#zzXnxq").val("");
		}
		if ($.founded(qsxnxq)) {
			$("#zzXnxq option").each(function() {
				var opt = $(this).val();
				if (qsxnxq*1 > opt*1) {
					$(this).hide();
				}
				$('#zzXnxq').trigger("chosen:updated");
			});
		}
	});
	
	var colModel = [{label:'学号',name:'xh', index: 'xh',align:'center',width:'136px'},
	    			{label:'姓名',name:'xm', index: 'xm',align:'center',width:'116px'},
	    			{label:'平均学分绩点',name:'pjxfjd', index: 'pjxfjd',align:'center',width:'101px',isnumber:true},
					{label:'名次',name:'pm', index: 'pm',align:'center',width:'148px',isnumber:true},
		    		{label:'学院',name:'jgmc', index: 'jgmc',align:'center',width:'130px'},
					{label:'年级',name:'njmc', index: 'njmc',align:'center',width:'60px'},
					{label:'专业',name:'zymc', index: 'zymc',align:'center',width:'125px'},
					{label:'班级',name:'bj', index: 'bj',align:'center',width:'115px'}];
	//列表
	var TempGrid = $.extend({},BaseJqGrid,{  
		postData	: paramMap(),		
		pager		: "#pager", //分页工具栏  
		resizeHandle:"#searBox",
//		height	    : "715px",
		datatype	: "local", 
		rowNum 		: 50, // 每页显示记录数
		rowList 	: [50, 100, 500, 1500, 2500, 3500, 4500, 5000], // 可调整每页显示的记录数
	    url			: _path + '/cjpmtj/cjpmtj_cxPjxfjdpmcxIndex.html?doType=query', //这是Action的请求地址  
	    colModel	: colModel,
		sortname: 'xh', //首次加载要进行排序的字段 
	 	sortorder: 'asc'		
	});
	$('#tabGrid').jqGridWrap(TempGrid);
	
	//查询事件
	$("#btn_cx").click(function(event) {
		search("tabGrid", paramMap());
	});	
	
	$("#btn_dy").click(function() {
		$("#progressbar").data("finished",false);
		$.post(_path + '/cjpmtj/cjpmtj_dyPjxfjdzm.html', paramMap(), function (filePath) {
			if (filePath.indexOf("成功") > -1) {
				if (isIE()) {
					checkIEhasPdfReader();
					window.open(filePath.split("#")[0]);
				} else {
					window.open(filePath.split("#")[0]);
				}
			} else {
				$.alert(filePath);
			}
		}, "json", {
			//显示提交进度的状态条元素
			progressElement: "#progressbar",
			//进度处理完成后进度归零延时时间；单位毫秒，默认2000
			progressDelay: 2000,
			//定时请求处理进度Ajax执行周期；单位毫秒，默认400
			progressPeriod: 400,
			//进度回调请求URL【该路径为通用路径，必须传参数key= 指定的值 】
			progressURL: _path + "/xtgl/progress_cxProgressStatus.html?key=zmdy_print_processed_key"
		});
        return false;
	});
	
	$("#kz_lr").click(function(e) {
		if($("#lz_l").is(":visible")){
			$("#lz_l").hide();
			$("#lz_r").removeClass("col-md-8 col-sm-6").addClass("col-sm-12 col-md-12 col-lg-12");
			$(this).children("a").attr("title","展开");
			$(this).children("a").children("img").attr("src",_stylePath+"/assets/images/ico_r.png");
		}else{
			$("#lz_l").show();
			$("#lz_r").removeClass("col-sm-12 col-md-12 col-lg-12").addClass("col-md-8 col-sm-6");
			$(this).children("a").attr("title","隐藏");
			$(this).children("a").children("img").attr("src",_stylePath+"/assets/images/ico_l.png");
		}
	});
})

function paramMap(){
	var map = {
		"qsXnxq" : $("#qsXnxq").val(),
		"zzXnxq" : $("#zzXnxq").val(),
		"cjxzm"  : $("input:radio[name='cjxzm']:checked").val(),
		"tjfw"   : $("input:radio[name='tjfw']:checked").val()
	}
	if ($.founded($("[name=cjbjArr]:checked").val())) {
		var cjbjArr = [];
		$("input:checkbox[name='cjbjArr']:checked").each(function(i,item){
			cjbjArr.push($(item).val());
		});
		map["cjbjArr"] = cjbjArr.join(",");
	}
	return map;
}

function isIE(){
	return /msie/.test(navigator.userAgent.toLowerCase());
};

function checkIEhasPdfReader(){
	var bool = false;
	if(hasReader()||hasReaderActiveX()){
		bool = true;
	}else{
		$.error("未检测到Adobe Reader，请安装,否则可能会无法正常打印!",function() {
		});
	}
	return bool;
};

function hasReader(){
	 var i,            
	 n = navigator.plugins,            
	 count = n.length,            
	 regx = /Adobe Reader|Adobe PDF|Acrobat/gi;  
	 if(count>0){
		 for(i=0; i<count; i++){
		 if(regx.test(n[i].name)){  
		    return true;            
		   }        
		 }
	 }
	 return false;  
}
	 
function hasReaderActiveX(){  
	 var axObj = null;
	 if (window.ActiveXObject) { 
	 axObj = createAXO("AcroPDF.PDF");   
	 if(!axObj){
		 axObj = createAXO("PDF.PdfCtrl"); 
		 }           
	  if (axObj !== null) { 
		  return true; 
		  }        
	  }        
	  return false;    
}; 	
	  
function createAXO (type){        
	var ax;        
	try {            
	ax = new ActiveXObject(type);        
	} catch (e) {            
	 ax = null;        
	}       
	 return ax;    
}; 