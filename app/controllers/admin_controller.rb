# redMine - project management software
# Copyright (C) 2006  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class AdminController < ApplicationController
  layout 'base'	
  before_filter :require_admin

  helper :sort
  include SortHelper	

  def index	
  end
	
  def projects
    sort_init 'name', 'asc'
    sort_update
    
    @status = params[:status] ? params[:status].to_i : 0
    conditions = nil
    conditions = ["status=?", @status] unless @status == 0
    
    @project_count = Project.count(:conditions => conditions)
    @project_pages = Paginator.new self, @project_count,
								25,
								params['page']								
    @projects = Project.find :all, :order => sort_clause,
                        :conditions => conditions,
						:limit  =>  @project_pages.items_per_page,
						:offset =>  @project_pages.current.offset

    render :action => "projects", :layout => false if request.xhr?
  end

  def mail_options
    @actions = Permission.find(:all, :conditions => ["mail_option=?", true]) || []
    if request.post?
      @actions.each { |a|
        a.mail_enabled = (params[:action_ids] || []).include? a.id.to_s 
        a.save
      }
      flash.now[:notice] = l(:notice_successful_update)
    end
  end
  
  def info
    @db_adapter_name = ActiveRecord::Base.connection.adapter_name
    @flags = Hash.new
    @flags[:default_admin_changed] = User.find(:first, :conditions => ["login=? and hashed_password=?", 'admin', User.hash_password('admin')]).nil?
    @flags[:file_repository_writable] = File.writable?(Attachment.storage_path)
    @flags[:textile_available] = ActionView::Helpers::TextHelper.method_defined? "textilize"
  end  
end
