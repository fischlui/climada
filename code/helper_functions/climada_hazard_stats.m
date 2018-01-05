function hazard = climada_hazard_stats(hazard,return_periods,check_plot,fontsize,store_stats2hazard)
% NAME:
%   climada_hazard_stats
% PURPOSE:
%   plot hazard intensity maps for different return periods, based on the
%   probabilistic (and/or historic) data set. On output, the statistics are
%   available, directly added to the hazard structure.
%
%   If called with the output hazard on subsequent calls, only the plotting
%   needs to be done (e.g. to further improve plots). The code checks for
%   hazard.stats still to be valid for requested return periods (and
%   whether historic events only). To repeat calculation of the maps,
%   delete hazard.stats.
%
%   See also climada_IFC_plot for a local hazard intensity/frequency plot
%
%   NOTE: this code listens to climada_global.parfor for substantial speedup
%
%   PROGRAMMERS APOLOGY: in order to process huge hazard sets, the special
%   option 'global' is provided. This is not elegant style, but prevents
%   from passing on a huge variable, in which case MATLAB makes a copy (and
%   hence starts swapping for huge hazard sets...).
%
%   previous call: e.g. climada_tc_hazard_set
% CALLING SEQUENCE:
%   climada_hazard_stats(hazard,return_periods,check_plot)
% EXAMPLE:
%   hazard=climada_hazard_load('TCNA_today_small'); % load a hazard set
%   climada_hazard_stats(hazard);
%   climada_hazard_stats(hazard,[1 2 10 20],-1); % show historic events only
%   hazard_stats_only=climada_hazard_stats(hazard,[1 2 10 20],-10,12,-1); % return stats only
%                     climada_hazard_stats(hazard,[1 2 10 20],-10,12,'hazard_stats'); % save stats to file
%hazard_stats_hist = climada_hazard_stats(hazard,[10 25 50 100 250 500 1000],-10,12,-1);
%hazard_stats      = climada_hazard_stats(hazard,[10 25 50 100 250 500 1000],  0,12,-1)
%
%   global hazard % define hazard as global variable
%   load('WISC_eur_WS'); % better use load than climada_hazard_load
%   climada_hazard_stats('global',[10 25 50 100 250 500 1000],-10); % operate on global variable hazard
% INPUTS:
%   hazard: hazard structure, as generated by e.g. climada_tc_hazard_set
%       ='global': define hazard as a global variable before calling, in
%       which case its workspace is shared and prevents from passing on a
%       huge variable, in which case MATLAB makes a copy (and hence starts
%       swapping for huge hazard sets...). In this case, do NOT specify any
%       ouput (as otherwise, there might be troubles in return).
%       > prompted for if not given
% OPTIONAL INPUT PARAMETERS:
%   return_periods: vector containing the requested return periods
%       (default=[50 50 100 250])
%   check_plot: default=1, draw the intensity maps for various return
%       periods for the full hazard set. Set=0 to omit plot
%       =-1: calculate and plot the return period maps based on historic
%       events only (needs hazard.orig_event_flag to exist)
%       =-10: as -1, but do NOT PLOT, just return historic
%   fontsize: default =12
%   store_stats2hazard: if =1 (default), store hazard.stats
%       =-1: ONLY return stats, i.e. only key fields (hazard.lon, .lat, .peril_ID,
%       .units) and hazard.stats added, but fields like intensity not
%       returned. Useful if one wants to obtain stats of a very large
%       hazard set (see also hazard='global' above for a huge hazard) and
%       hence avoid storing more than necessary twice.  
%       If store_stats2hazard is a character (path and filename), it sets
%       hazard.filename=store_stats2hazard, then sets store_stats2hazard=-1 and
%       stores hazard (with hazard.stats only) to hazard.filename (if it
%       does not exist yet, for safety reasons to avoid overwriting hazard). 
% OUTPUTS:
%   the field hazard.stats is added to the hazard structure, with
%       historic: =1 if for historic events only, see check_plot=-1 or -10
%       return_period(i): return period i
%       intensity(i,j): intensity for return period i at centroid j
% MODIFICATION HISTORY:
% Lea Mueller, muellele@gmail.com, 20110623
% David N. Bresch, david.bresch@gmail.com, 20130317 cleanup
% David N. Bresch, david.bresch@gmail.com, 20140411 fixed some non-TC issues
% David N. Bresch, david.bresch@gmail.com, 20150114, Octave compatibility for -v7.3 mat-files
% Lea Mueller, muellele@gmail.com, 20150607, change tc max int. value to 80 instead of 100m/s
% Lea Mueller, muellele@gmail.com, 20150607, add cross for San Salvador in plot, for San Salvador only
% Lea Mueller, muellele@gmail.com, 20150716, add landslides option (LS) with specific colormap, intensities from 0 to 1
% David N. Bresch, david.bresch@gmail.com, 20160527, complete overhaul, new field hazard.stats
% David N. Bresch, david.bresch@gmail.com, 20160529, otherwise in colorscale selection fixed
% David N. Bresch, david.bresch@gmail.com, 20160529, new default return periods (6)
% David N. Bresch, david.bresch@gmail.com, 20161006, minimum thresholds set for some perils
% David N. Bresch, david.bresch@gmail.com, 20170202, parallelized
% David N. Bresch, david.bresch@gmail.com, 20170216, small issue in line 274 (not fixed yet)
% David N. Bresch, david.bresch@gmail.com, 20170518, small fix for EQ (caxis_max)
% David N. Bresch, david.bresch@gmail.com, 20171229, plot distribution improved
% David N. Bresch, david.bresch@gmail.com, 20171230, climada_progress2stdout and additional vertical colorbar
% David N. Bresch, david.bresch@gmail.com, 20180101, hazard.map renamed to hazard.stats, peril-specific plot settings streamlined
% David N. Bresch, david.bresch@gmail.com, 20180103, store_stats2hazard added
% David N. Bresch, david.bresch@gmail.com, 20180105, hazard='global' added
%-

% init global variables
global climada_global
if ~climada_init_vars, return; end

% poor man's version to check arguments
if ~exist('hazard'             , 'var'), hazard         = []; end
if ~exist('return_periods'     , 'var'), return_periods = []; end
if ~exist('check_plot'         , 'var'), check_plot     = 1 ; end
if ~exist('fontsize'           , 'var'), fontsize       = 12 ; end
if ~exist('store_stats2hazard' , 'var'), store_stats2hazard = 1 ; end

if strcmpi(hazard,'global')
    % see PROGRAMMERS APOLOGY in header
    clear hazard
    fprintf('working on global hazard\n')
    global hazard % the parser does not like this, we know ;-)
    store_stats2hazard=1; % avoid troubles
else
    hazard=climada_hazard_load(hazard);
end

if ischar(store_stats2hazard)
    hazard_filename=store_stats2hazard;
    % complete path, if missing
    [fP,fN,fE]=fileparts(hazard_filename);
    if isempty(fP),fP=climada_global.hazards_dir;end
    if isempty(fE),fE='.mat';end
    hazard_filename=[fP filesep fN fE];
    store_stats2hazard=-1;
else
    hazard_filename='';
end

% Parameters
%
% set default return periods
%if isempty(return_periods'),return_periods = [10 25 50 100 500 1000];end % until 20180101
if isempty(return_periods'),return_periods = [25 50 100 250];end

hazard=climada_hazard_load(hazard);

% check if based on probabilistic tc track set
if isfield(hazard,'orig_event_flag') && check_plot<0
    sel_event_pos=find(hazard.orig_event_flag);
else
    sel_event_pos=1:length(hazard.frequency);
end

if check_plot<0
    hist_str='historic ';
    historic_flag=1;
    if check_plot<-1,check_plot=0;end
else
    hist_str='';
    historic_flag=0;
end

if ~isfield(hazard,'units'),hazard.units='';end
[cmap,c_ax,xtick_,cbar_str,intensity_threshold,hazard.units] = climada_colormap(hazard.peril_ID,'',hazard.units); % set defaults per peril
if isempty(cmap),cmap=colormap;end % default, if not returned
if isempty(c_ax),c_ax=[0 full(max(max(hazard.intensity)))];end % default, if not returned
cbar_str  = [hist_str cbar_str]; % pre-prend 'historic'

if isfield(hazard,'stats')
    erase_stats=1; % start from safe assumption
    % check wether the already calculated stats are still what's required
    if length(hazard.stats.return_period)==length(return_periods) % same number of return periods
        if sum(hazard.stats.return_period-return_periods)==0 % same return periods
            if abs(hazard.stats.historic-historic_flag)==0 % same event selection
                erase_stats=0;
            end
        end
    end
    if erase_stats,hazard=rmfield(hazard,'stats');end
end

% calculation
% -----------

if ~isfield(hazard,'stats')
    
    n_return_periods         = length(return_periods);
    n_centroids              = size(hazard.intensity,2);
    n_events                 = length(hazard.frequency);
    n_sel_event              = length(sel_event_pos);
    
    nonzero_intensity=sum(hazard.intensity(sel_event_pos,:),1);
    nonzero_centroid_pos=find(nonzero_intensity);
    n_nonzero_centroids=length(nonzero_centroid_pos);
    intensity_stats=zeros(n_return_periods,n_nonzero_centroids);
    
    intensity=hazard.intensity(sel_event_pos,nonzero_centroid_pos);
    frequency=hazard.frequency(sel_event_pos)*n_events/n_sel_event;
        
    t0 = clock;
    if climada_global.parfor
        
        fprintf('calculate hazard statistics: processing %i %sevents at %i (non-zero) centroids (parfor)\n',n_sel_event,hist_str,n_nonzero_centroids);

        parfor centroid_i = 1:n_nonzero_centroids
            intensity_stats(:,centroid_i)=LOCAL_intensity_stats(intensity(:,centroid_i),intensity_threshold,frequency,return_periods);
        end % centroid_i
    else
        
        fprintf('calculate hazard statistics: processing %i %sevents at %i (non-zero) centroids\n',n_sel_event,hist_str,n_nonzero_centroids);

        climada_progress2stdout % init
        mod_step = 100;
        if n_centroids>10000,mod_step=1000;end
        if n_centroids>100000,mod_step=10000;end
        for centroid_i = 1:n_nonzero_centroids
            intensity_stats(:,centroid_i)=LOCAL_intensity_stats(intensity(:,centroid_i),intensity_threshold,frequency,return_periods);
            
            climada_progress2stdout(centroid_i,n_centroids,mod_step,'centroids'); % update
            
        end % centroid_i
        climada_progress2stdout(0) % terminate
    end
    fprintf('processing %i non-zero centroids took %2.2f sec\n',n_nonzero_centroids,etime(clock,t0));
    
    if store_stats2hazard==-1 % only keep stats, delete intensity upon return etc.
        lon=hazard.lon;
        lat=hazard.lat;
        peril_ID=hazard.peril_ID;
        event_ID=hazard.event_ID;
        centroid_ID=hazard.centroid_ID;
        units=hazard.units;
        clear hazard;
        hazard.lon=lon;
        hazard.lat=lat;
        hazard.peril_ID=peril_ID;
        hazard.units=units;
        hazard.event_ID=event_ID;
        hazard.centroid_ID=centroid_ID;
		hazard.intensity=[];
		hazard.frequency=[];
    end
    
    % store stats to output
    hazard.stats.historic      = historic_flag;
    hazard.stats.return_period = return_periods;
    hazard.stats.intensity     = spalloc(n_return_periods,n_centroids,ceil(n_return_periods*n_nonzero_centroids)); % allocate
    hazard.stats.intensity(:,nonzero_centroid_pos)=intensity_stats;clear intensity_stats % fill in
        
    if ~isempty(hazard_filename)
        if ~exist(hazard_filename,'file')
            hazard.filename=hazard_filename;
            fprintf('> storing hazard with stats to only to %s\n',hazard.filename);
            save(hazard.filename,'hazard',climada_global.save_file_version);
        else
            fprintf('WARNING: %s already exists, not overwritten\n',hazard.filename);
        end
    end
    
end % calculation

% figures
% -------

if abs(check_plot)>0
    
    n_return_periods=length(hazard.stats.return_period);
    fprintf('plotting %i %sintensity vs return period maps (be patient) ',n_return_periods,hist_str)
    
    scale = max(hazard.lon)-min(hazard.lon);
    centroids.lon=hazard.lon; % to pass on below
    centroids.lat=hazard.lat; % to pass on below
    
    % figure how many plots and how to place
    n_return_periods = length(hazard.stats.return_period);
    subplots_hor = ceil(sqrt(n_return_periods));
    subplots_ver = ceil(n_return_periods/subplots_hor);
    
    subaxis(subplots_ver, subplots_hor, 1,'MarginTop',0.15, 'mb',0.05)
    
    % horizontal colorbar
    subaxis(subplots_hor); % upper right plot
    pos = get(subaxis(subplots_hor),'pos');
    % distance in normalized units from the top of the axes
    dist = .03;
    hcbar_hor=colorbar('location','northoutside', 'position',[pos(1) pos(2)+pos(4)+dist pos(3) dist*.75]);
    set(get(hcbar_hor,'xlabel'),'String',cbar_str,'FontSize',fontsize);
    set(hcbar_hor,'XTick',xtick_);set(hcbar_hor,  'FontSize',fontsize)
    colormap(cmap);caxis(c_ax)
    set(gca,'FontSize',fontsize)
    hold on
    
    % vertical colorbar
    subaxis(2*subplots_hor); % lower or middle right plot
    pos = get(subaxis(2*subplots_hor),'pos');
    dist = .01;pos(1)=pos(1)+pos(3)+dist;pos(3)=1.5*dist; % in normalized units
    hcbar_ver=colorbar('Location','EastOutside','Position',pos);
    set(get(hcbar_ver,'xlabel'),'String',cbar_str,'FontSize',fontsize);
    set(hcbar_ver,'XTick',xtick_);set(hcbar_ver,  'FontSize',fontsize)
    colormap(cmap);caxis(c_ax)
    set(gca,'fontsize',fontsize);axis off
    hold on
    
    for rp_i=1:n_return_periods
        
        fprintf('.') % simplest progress indicator
        subaxis(rp_i)
        
        values = full(hazard.stats.intensity(rp_i,:));
        
        if sum(values(not(isnan(values))))>0 % nansum(values)>0
            [X, Y, gridded_VALUE] = climada_gridded_VALUE(values, centroids);
            gridded_VALUE(gridded_VALUE<0.1) = NaN; % avoid tiny values
            contourf(X, Y, gridded_VALUE,200,'linecolor','none')
        else
            text(mean([min(hazard.lon) max(hazard.lon)]),...
                mean([min(hazard.lat ) max(hazard.lat )]),...
                'no data for this return period available','fontsize',10,...
                'HorizontalAlignment','center')
        end
        hold on
        climada_plot_world_borders(2,'','',0,[],[0 0 0])
        title([int2str(hazard.stats.return_period(rp_i)) ' yr'],'fontsize',fontsize);
        axis([min(hazard.lon)-scale/30  max(hazard.lon)+scale/30 ...
            min(hazard.lat )-scale/30  max(hazard.lat )+scale/30])
        % do not display xticks, nor yticks
        set(subaxis(rp_i),'xtick',[],'ytick',[],'DataAspectRatio',[1 1 1])
        colormap(cmap);caxis(c_ax)
        set(gca,'FontSize',fontsize)
        axis on
        hold on
        
        %if ~exist('cmap','var'), cmap = '';end
        %if ~isempty(cmap), colormap(cmap);end
        %set(hcbar_hor,'XTick',xtick_);set(hcbar_ver,'XTick',xtick_)
        
    end % rp_i
    
    set(gcf,'Position',[427 29 574 644]);
    drawnow
    fprintf(' done\n')
    
end % figures

end % climada_hazard_stats

function intensity_stats=LOCAL_intensity_stats(intensity,intensity_threshold,frequency,return_periods)
[intensity_pos,ind_int] = sort(intensity,'descend');
if sum(intensity_pos)>0 % otherwise no intensity above threshold
    frequency2 = frequency;
    intensity_pos              = full(intensity_pos);
    below_thresh_pos           = intensity_pos<intensity_threshold;
    intensity_pos(intensity_pos<intensity_threshold) = [];
    frequency2 = frequency2(ind_int); % sort frequency accordingly
    frequency2(below_thresh_pos) = [];
    freq            = cumsum(frequency2(1:length(intensity_pos)))'; % exceedence frequency
    if length(freq)>1
        p           = polyfit(log(freq), intensity_pos, 1);
    else
        p = zeros(2,1);
    end
    exc_freq      = 1./return_periods;
    intensity_fit = polyval(p, log(exc_freq));
    intensity_fit(intensity_fit<=0)    = 0; %nan;
    R                                  = 1./freq;
    try
        neg                                = return_periods >max(R);
    catch
        intensity_stats=zeros(length(return_periods),1);
        return
    end
    intensity_fit(neg)                 = 0; %nan;
    intensity_stats = intensity_fit;
else
    intensity_stats=zeros(length(return_periods),1);
end % sum(intensity_pos)>0 %
end % LOCAL_intensity_stats