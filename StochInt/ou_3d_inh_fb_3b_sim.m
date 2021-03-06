function [g_1,g_2,g_3,t_vec]=ou_3d_inh_fb_3b_sim(ou_drift,ou_leak,ou_cov,ou_init,fb_add_const,fb_gain,a_1,a_2,a_3,delta_t,process_range,max_time,num_sim,runmed_width)
% Estimate of the first passage time densities for a (time-variant)
% 3D Ornstein-Uhlenbeck process with inhibitory feedback from the output
% of the other two integrators to the input of a particular integrator
% and 3 (time-variant) boundaries based on a simulation.
%
% J. Ditterich, 1/09
%
% [g_1,g_2,g_3,t_vec] = ou_3d_inh_fb_3b_sim (ou_drift,ou_leak,ou_cov,ou_init,fb_add_const,
%                                            fb_gain,a_1,a_2,a_3,delta_t,
%                                            process_range,max_time,num_sim[,runmed_width])
%
% g_1 is the first passage time density for the first boundary multiplied
%     by the probability of hitting the first boundary first, evaluated
%     at the times given in t_vec.
% g_2 is the first passage time density for the second boundary multiplied
%     by the probability of hitting the second boundary first, evaluated
%     at the times given in t_vec.
% g_3 is the first passage time density for the third boundary multiplied
%     by the probability of hitting the third boundary first, evaluated
%     at the times given in t_vec.
%
% ou_drift is the drift vector of the OU process. It can either be a vector of length 3 or,
%          for the time-variant case, the name of a function, which must return
%          the drift vector when called with the time as the argument.
% ou_leak defines the "leakiness" of the integrator(s) and has to be a scalar.
%         The deterministic part of the stochastic differential equation,
%         ignoring the inhibitory feedback, is given by
%         ou_drift - ou_leak * current_value. A Wiener process can be studied
%         by setting ou_leak to 0.
% ou_cov is the covariance matrix of the OU process. It can either be a 3-by-3 matrix or,
%        for the time-variant case, the name of a function, which must return
%        the covariance matrix when called with the time as the argument.
%        The absolute value of the correlation coefficients must be smaller than 1.
%        Please use a 2D function for fully correlated processes.
% ou_init is the initial vector of the OU process. It must be a vector of length 3.
% fb_add_const is a constant (scalar) that is added to the sum of the
%              outputs of the other two integrators before everything is
%              multiplied with fb_gain and subtracted from the input to the
%              integrator.
% fb_gain is a factor (scalar) for scaling the inhibitory feedback signal
%         before it is applied to the input of the integrator. A value of 0
%         deactivates the feedback. The deterministic part of the
%         stochastic differential equation is given by
%         ou_drift - ou_leak * current_value - fb_gain *
%         (sum of current values of other two integrators + fb_add_const).
% a_1 defines the first absorbing boundary. a_1 is the name of a function,
%     which must return 1, if a certain location is located on or outside the boundary,
%     and 0, if a certain location is located inside the boundary, when called
%     with a 1-by-3 vector defining the location as the first and time as the
%     second argument.
% a_2 defines the second absorbing boundary. See a_1 for the format. The boundaries
%     should be defined in such a way that "boundary crossed" regions do not
%     overlap. Since the algorithm checks the first boundary first, a crossing of
%     multiple boundaries in the same time step will be registered as a crossing of
%     the first boundary.
% a_3 defines the third absorbing boundary. See a_1 for the format. The boundaries
%     should be defined in such a way that "boundary crossed" regions do not
%     overlap. Since the algorithm checks the first boundary first, a crossing of
%     multiple boundaries in the same time step will be registered as a crossing of
%     the first boundary.
% delta_t is the temporal step size.
% process_range defines the valid process range. It normally has to be a 3-by-2 matrix.
%               The first row defines the lower and the upper limit of the first dimension,
%               the second row the lower and the upper limit of the second dimension,
%               and the third row the lower and the upper limit of the third dimension.
%               Make sure that you define the boundaries in such a way that they are
%               located within this range. Otherwise the algorithm will block.
%               Limiting the process range allows to study the development of the variance
%               of processes with natural limits. When passing 0 the process range is
%               unlimited.
% max_time defines the maximum first passage time taken into account by the algorithm.
% num_sim is the number of simulations used for calculating the result.
% runmed_width is an optional parameter, which defines the width of a running median filter
%              applied to the output. It has to be an odd number. 0 deactivates the filter.
%              The default value is 0.

% History:
% released on 8/13/10 as part of toolbox V 2.7

if nargin<14 % runmed_width not given?
    runmed_width=0; % default value
end;

num_sim=round(num_sim);
runmed_width=round(runmed_width);

% Some checks
if isnumeric(ou_drift)&&(length(ou_drift)~=3)
    error('OU_3D_INH_FB_3B_SIM: OU_DRIFT must be either a vector of length 3 or the name of a function!');
end;

if isnumeric(ou_drift)&&(size(ou_drift,1)==3) % wrong orientation?
    ou_drift=ou_drift'; % transpose it
end;

if ou_leak<0
    error('OU_3D_INH_FB_3B_SIM: OU_LEAK must be a non-negative number!');
end;

if isnumeric(ou_cov)&&((size(ou_cov,1)~=3)||(size(ou_cov,2)~=3))
    error('OU_3D_INH_FB_3B_SIM: OU_COV must either be a 3-by-3 matrix or the name of a function!');
end;

if isnumeric(ou_cov)&&((ou_cov(1,1)<=0)||(ou_cov(2,2)<=0)||(ou_cov(3,3)<=0))
    error('OU_3D_INH_FB_3B_SIM: The main diagonal elements of OU_COV must be positive!');
end;

if isnumeric(ou_cov)&&(det(ou_cov)==0)
    error('OU_3D_INH_FB_3B_SIM: The covariance matrix must not be singular!');
end;

if isnumeric(ou_cov)&&((det(ou_cov)<0)||(ou_cov(1,2)~=ou_cov(2,1))||(ou_cov(1,3)~=ou_cov(3,1))||(ou_cov(2,3)~=ou_cov(3,2)))
    error('OU_3D_INH_FB_3B_SIM: Invalid covariance matrix!');
end;

if ~((size(ou_init,1)==1)&&(size(ou_init,2)==3))&&~((size(ou_init,1)==3)&&(size(ou_init,2)==1))
    error('OU_3D_INH_FB_3B_SIM: OU_INIT must be a vector of length 3!');
end;

if size(ou_init,1)==3 % wrong orientation?
    ou_init=ou_init'; % transpose it
end;

if fb_gain<0
    error('OU_3D_INH_FB_3B_SIM: FB_GAIN must not be negative! The system would not be stable.');
end;

if delta_t<=0
    error('OU_3D_INH_FB_3B_SIM: The time step must be a positive number!');
end;

if (size(process_range,1)~=3)||(size(process_range,2)~=2)
    if (size(process_range,1)~=1)||(size(process_range,2)~=1)||(process_range~=0)
        error('OU_3D_INH_FB_3B_SIM: PROCESS_RANGE must either be a 3-by-2 matrix or 0!');
    end;
end;

limited_range=(size(process_range,1)==3); % limited range?

if limited_range
    if (diff(process_range(1,:))<0)||(diff(process_range(2,:))<0)||(diff(process_range(3,:))<0) % screwed up range?
        error('OU_3D_INH_FB_3B_SIM: Invalid range!');
    end;
end;

if limited_range
    if (ou_init(1)<process_range(1,1))||(ou_init(1)>process_range(1,2))||(ou_init(2)<process_range(2,1))||(ou_init(2)>process_range(2,2))||(ou_init(3)<process_range(3,1))||(ou_init(3)>process_range(3,2))
        error('OU_3D_INH_FB_3B_SIM: Initial value out of range!');
    end;
end;

if max_time<=0
    error('OU_3D_INH_FB_3B_SIM: MAX_TIME must be a positive number!');
end;

if num_sim<1
    error('OU_3D_INH_FB_3B_SIM: A minimum of 1 simulation is required!');
end;

if runmed_width<0
    error('OU_3D_INH_FB_3B_SIM: RUNMED_WIDTH must not be negative!');
end;

if runmed_width&&(~mod(runmed_width,2))
    error('OU_3D_INH_FB_3B_SIM: RUNMED_WIDTH must be an odd number!');
end;

% Initialization
vec_length=floor(max_time/delta_t);
t_vec=delta_t:delta_t:vec_length*delta_t;
g_1=zeros(1,vec_length);
g_2=zeros(1,vec_length);
g_3=zeros(1,vec_length);

if isnumeric(ou_drift) % Is the drift time-invariant?
    drift_const=1;
    drift_cur=ou_drift*delta_t;
else
    drift_const=0;
end;

if isnumeric(ou_cov) % Is the covariance matrix time-invariant?
    cov_const=1;
    sqrtm_cov_cur=sqrtm(ou_cov*delta_t);
else
    cov_const=0;
end;

% Loop
for k=1:num_sim
    boundary_tested=0;
    
    % create a trajectory with a length of vec_length
    if cov_const&&drift_const&&(ou_leak==0)&&(fb_gain==0)&&(limited_range==0) % In this case we can do it in a single step.
        rand_vec=random('norm',0,1,3,vec_length); % independent noise
        rand_vec=repmat(drift_cur',1,vec_length)+sqrtm_cov_cur*rand_vec; % drift & correlated noise
        cur_traj=(repmat(ou_init,vec_length,1)+tril(ones(vec_length,vec_length))*rand_vec')'; % integration
    elseif cov_const&&(ou_leak==0)&&(fb_gain==0)&&(limited_range==0) % This case is not much more difficult ...
        rand_vec=random('norm',0,1,3,vec_length); % independent noise
        rand_vec=sqrtm_cov_cur*rand_vec; % correlated noise
        
        for i=1:vec_length
            temp=feval(ou_drift,i*delta_t); % get current drift
            
            if ~((size(temp,1)==1)&&(size(temp,2)==3))&&~((size(temp,1)==3)&&(size(temp,2)==1))
                error('OU_3D_INH_FB_3B_SIM: The drift returned by a function must be a vector of length 3!');
            end;
            
            if size(temp,2)==3 % wrong orientation?
                temp=temp'; % transpose it
            end;
            
            rand_vec(:,i)=rand_vec(:,i)+temp*delta_t; % drift part
        end;
        
        cur_traj=(repmat(ou_init,vec_length,1)+tril(ones(vec_length,vec_length))*rand_vec')'; % integration
    else % separate random calls necessary
        boundary_tested=1;
        cur_val=ou_init; % start with the initial value
        cur_traj=[];
        
        for i=1:vec_length
            saved_cur_val=cur_val;
            
            if ou_leak>0 % OU process?
                cur_val=cur_val*(1-ou_leak*delta_t); % leaky integrator part
            end;
            
            if fb_gain>0 % inhibitory feedback?
                cur_val=cur_val-(saved_cur_val*[0 1 1;1 0 1;1 1 0]+fb_add_const)*fb_gain*delta_t; % inhibitory feedback
            end;
            
            if drift_const % time-invariant drift?
                cur_val=cur_val+drift_cur; % drift part
            else
                temp=feval(ou_drift,i*delta_t); % get current drift
                
                if ~((size(temp,1)==1)&&(size(temp,2)==3))&&~((size(temp,1)==3)&&(size(temp,2)==1))
                    error('OU_3D_INH_FB_3B_SIM: The drift returned by a function must be a vector of length 3!');
                end;
                
                if size(temp,1)==3 % wrong orientation?
                    temp=temp'; % transpose it
                end;
                
                cur_val=cur_val+temp*delta_t;
            end;
            
            if cov_const % time-invariant covariance matrix?
                rand_vec=random('norm',0,1,3,1); % independent noise
                rand_vec=sqrtm_cov_cur*rand_vec; % correlated noise
                cur_val=cur_val+rand_vec'; % noise part
            else
                temp=feval(ou_cov,i*delta_t); % get current covariance matrix
                
                if (size(temp,1)~=3)||(size(temp,2)~=3)
                    error('OU_3D_INH_FB_3B_SIM: The covariance matrix returned by a function must be a 3-by-3 matrix!');
                end;
                
                if (temp(1,1)<=0)||(temp(2,2)<=0)||(temp(3,3)<=0)
                    error('OU_3D_INH_FB_3B_SIM: Algorithm stopped due to a non-positive variance!');
                end;
                
                if det(temp)==0
                    error('OU_3D_INH_FB_3B_SIM: Algorithm stopped due to a singular covariance matrix!');
                end;
                
                if (det(temp)<0)||(temp(1,2)~=temp(2,1))||(temp(1,3)~=temp(3,1))||(temp(2,3)~=temp(3,2))
                    error('OU_3D_INH_FB_3B_SIM: Algorithm stopped due to an invalid covariance matrix!');
                end;
                
                sqrtm_cov_cur=sqrtm(temp*delta_t);
                rand_vec=random('norm',0,1,3,1); % independent noise
                rand_vec=sqrtm_cov_cur*rand_vec; % correlated noise
                cur_val=cur_val+rand_vec'; % noise part
            end;
            
            if limited_range % Do we have to test the range?
                if cur_val(1)<process_range(1,1)
                    cur_val(1)=process_range(1,1);
                end;
                
                if cur_val(1)>process_range(1,2)
                    cur_val(1)=process_range(1,2);
                end;
                
                if cur_val(2)<process_range(2,1)
                    cur_val(2)=process_range(2,1);
                end;
                
                if cur_val(2)>process_range(2,2)
                    cur_val(2)=process_range(2,2);
                end;
                
                if cur_val(3)<process_range(3,1)
                    cur_val(3)=process_range(3,1);
                end;
                
                if cur_val(3)>process_range(3,2)
                    cur_val(3)=process_range(3,2);
                end;
            end;
            
            if feval(a_1,cur_val,i*delta_t) % first boundary crossed?
                g_1(i)=g_1(i)+1; % register boundary crossing
                break; % We no longer have to calculate the rest of the trajectory.
            end;
            
            if feval(a_2,cur_val,i*delta_t) % second boundary crossed?
                g_2(i)=g_2(i)+1; % register boundary crossing
                break; % We no longer have to calculate the rest of the trajectory.
            end;
            
            if feval(a_3,cur_val,i*delta_t) % third boundary crossed?
                g_3(i)=g_3(i)+1; % register boundary crossing
                break; % We no longer have to calculate the rest of the trajectory.
            end;
        end; % for i
    end;
    
    % check for boundary crossing
    if ~boundary_tested    
        for i=1:vec_length
            if feval(a_1,cur_traj(:,i)',i*delta_t) % first boundary crossed?
                g_1(i)=g_1(i)+1; % register boundary crossing
                break;
            end;

            if feval(a_2,cur_traj(:,i)',i*delta_t) % second boundary crossed?
                g_2(i)=g_2(i)+1; % register boundary crossing
                break;
            end;

            if feval(a_3,cur_traj(:,i)',i*delta_t) % third boundary crossed?
                g_3(i)=g_3(i)+1; % register boundary crossing
                break;
            end;
        end;
    end;
end;

g_1=g_1/num_sim/delta_t;
g_2=g_2/num_sim/delta_t;
g_3=g_3/num_sim/delta_t;
    
if runmed_width % filtering?
    g_1=runmed(g_1,runmed_width,1,0);
    g_2=runmed(g_2,runmed_width,1,0);
    g_3=runmed(g_3,runmed_width,1,0);
end;
