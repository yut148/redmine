# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
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

require 'SVG/Graph/Bar'
require 'SVG/Graph/BarHorizontal'
require 'digest/sha1'

class RepositoriesController < ApplicationController
  layout 'base'
  before_filter :find_project, :except => [:update_form]
  before_filter :authorize, :except => [:update_form]
  accept_key_auth :revisions
  
  def show
    # check if new revisions have been committed in the repository
    @repository.fetch_changesets if Setting.autofetch_changesets?
    # get entries for the browse frame
    @entries = @repository.entries('')    
    # latest changesets
    @changesets = @repository.changesets.find(:all, :limit => 10, :order => "committed_on DESC")
    show_error and return unless @entries || @changesets.any?
  end
  
  def browse
    @entries = @repository.entries(@path, @rev)
    show_error and return unless @entries    
  end
  
  def changes
    @entry = @repository.scm.entry(@path, @rev)
    show_error and return unless @entry
    @changes = Change.find(:all, :include => :changeset, 
                                 :conditions => ["repository_id = ? AND path = ?", @repository.id, @path.with_leading_slash],
                                 :order => "committed_on DESC")
  end
  
  def revisions
    @changeset_count = @repository.changesets.count
    @changeset_pages = Paginator.new self, @changeset_count,
								      25,
								      params['page']								
    @changesets = @repository.changesets.find(:all,
						:limit  =>  @changeset_pages.items_per_page,
						:offset =>  @changeset_pages.current.offset)

    respond_to do |format|
      format.html { render :layout => false if request.xhr? }
      format.atom { render_feed(@changesets, :title => "#{@project.name}: #{l(:label_revision_plural)}") }
    end
  end
  
  def entry
    @content = @repository.scm.cat(@path, @rev)
    show_error and return unless @content
    if 'raw' == params[:format]      
      send_data @content, :filename => @path.split('/').last
    end
  end
  
  def revision
    @changeset = @repository.changesets.find_by_revision(@rev)
    show_error and return unless @changeset
    @changes_count = @changeset.changes.size
    @changes_pages = Paginator.new self, @changes_count, 150, params['page']								
    @changes = @changeset.changes.find(:all,
  						:limit  =>  @changes_pages.items_per_page,
  						:offset =>  @changes_pages.current.offset)
  	
  	render :action => "revision", :layout => false if request.xhr?	
  end
  
  def diff
    @rev_to = params[:rev_to] ? params[:rev_to].to_i : (@rev - 1)
    @diff_type = ('sbs' == params[:type]) ? 'sbs' : 'inline'
    
    @cache_key = "repositories/diff/#{@repository.id}/" + Digest::MD5.hexdigest("#{@path}-#{@rev}-#{@rev_to}-#{@diff_type}")    
    unless read_fragment(@cache_key)
      @diff = @repository.diff(@path, @rev, @rev_to, type)
      show_error and return unless @diff
    end
  end
  
  def stats  
  end
  
  def graph
    data = nil    
    case params[:graph]
    when "commits_per_month"
      data = graph_commits_per_month(@repository)
    when "commits_per_author"
      data = graph_commits_per_author(@repository)
    end
    if data
      headers["Content-Type"] = "image/svg+xml"
      send_data(data, :type => "image/svg+xml", :disposition => "inline")
    else
      render_404
    end
  end
  
  def update_form
    @repository = Repository.factory(params[:repository_scm])
    render :partial => 'projects/repository', :locals => {:repository => @repository}
  end
  
private
  def find_project
    @project = Project.find(params[:id])
    @repository = @project.repository
    render_404 and return false unless @repository
    @path = params[:path].squeeze('/') if params[:path]
    @path ||= ''
    @rev = params[:rev].to_i if params[:rev]
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def show_error
    flash.now[:error] = l(:notice_scm_error)
    render :nothing => true, :layout => true
  end
  
  def graph_commits_per_month(repository)
    @date_to = Date.today
    @date_from = @date_to << 11
    @date_from = Date.civil(@date_from.year, @date_from.month, 1)
    commits_by_day = repository.changesets.count(:all, :group => :commit_date, :conditions => ["commit_date BETWEEN ? AND ?", @date_from, @date_to])
    commits_by_month = [0] * 12
    commits_by_day.each {|c| commits_by_month[c.first.to_date.months_ago] += c.last }

    changes_by_day = repository.changes.count(:all, :group => :commit_date, :conditions => ["commit_date BETWEEN ? AND ?", @date_from, @date_to])
    changes_by_month = [0] * 12
    changes_by_day.each {|c| changes_by_month[c.first.to_date.months_ago] += c.last }
   
    fields = []
    month_names = l(:actionview_datehelper_select_month_names_abbr).split(',')
    12.times {|m| fields << month_names[((Date.today.month - 1 - m) % 12)]}
  
    graph = SVG::Graph::Bar.new(
      :height => 300,
      :width => 500,
      :fields => fields.reverse,
      :stack => :side,
      :scale_integers => true,
      :step_x_labels => 2,
      :show_data_values => false,
      :graph_title => l(:label_commits_per_month),
      :show_graph_title => true
    )
    
    graph.add_data(
      :data => commits_by_month[0..11].reverse,
      :title => l(:label_revision_plural)
    )

    graph.add_data(
      :data => changes_by_month[0..11].reverse,
      :title => l(:label_change_plural)
    )
    
    graph.burn
  end

  def graph_commits_per_author(repository)
    commits_by_author = repository.changesets.count(:all, :group => :committer)
    commits_by_author.sort! {|x, y| x.last <=> y.last}

    changes_by_author = repository.changes.count(:all, :group => :committer)
    h = changes_by_author.inject({}) {|o, i| o[i.first] = i.last; o}
    
    fields = commits_by_author.collect {|r| r.first}
    commits_data = commits_by_author.collect {|r| r.last}
    changes_data = commits_by_author.collect {|r| h[r.first] || 0}
    
    fields = fields + [""]*(10 - fields.length) if fields.length<10
    commits_data = commits_data + [0]*(10 - commits_data.length) if commits_data.length<10
    changes_data = changes_data + [0]*(10 - changes_data.length) if changes_data.length<10
    
    graph = SVG::Graph::BarHorizontal.new(
      :height => 300,
      :width => 500,
      :fields => fields,
      :stack => :side,
      :scale_integers => true,
      :show_data_values => false,
      :rotate_y_labels => false,
      :graph_title => l(:label_commits_per_author),
      :show_graph_title => true
    )
    
    graph.add_data(
      :data => commits_data,
      :title => l(:label_revision_plural)
    )

    graph.add_data(
      :data => changes_data,
      :title => l(:label_change_plural)
    )
       
    graph.burn
  end

end
  
class Date
  def months_ago(date = Date.today)
    (date.year - self.year)*12 + (date.month - self.month)
  end

  def weeks_ago(date = Date.today)
    (date.year - self.year)*52 + (date.cweek - self.cweek)
  end
end

class String
  def with_leading_slash
    starts_with?('/') ? self : "/#{self}"
  end
end
