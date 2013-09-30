require 'gub/version'
require 'yaml'
require 'thor'
require 'octokit'
require 'terminal-table'

module Gub
  class CLI < Thor
    default_task :info
    
    desc 'publish', 'Publish a local repo to Github'
    def publish
      setup
    end
  
    desc 'repos', 'List Github repositories'
    def repos
      setup
      rows = []
      id = 0
      @client.repos.list.each do |repo|
        id = id.next
        rows << [id, repo.full_name]
      end
      @client.orgs.list.each do |org|
        @client.repos.list(org: org.login).each do |repo|
          id = id.next
          rows << [id, repo.full_name]
        end
      end
      puts table rows, ['#', 'Repository']
    end
  
    desc 'issues', 'List Github issues'
    method_options all: :boolean, default: false
    def issues
      setup
      if options.all || repo_full_name.nil?
        puts "Listing all issues:"
        issues = @client.issues
      else
        params = {}
        if parent
          params[:repo] = parent
        else
          params[:repo] = repo_full_name
        end
        puts "Listing issues for #{params[:repo]}:"
        issues = @client.issues params
      end
      unless issues.nil?
        rows = []
        issues.each do |issue|
          row = []
          row << issue.number
          row << issue.title
          row << issue.user.login
          row << (issue.assignee.nil? ? '' : issue.assignee.login)
          rows << row
        end
        puts table rows, ['ID', 'Title', 'Author', 'Assignee']
        puts "Found #{issues.count} issue(s)."
        puts 'Hint: use "gub start" to start working on an issue.'
      end
    # rescue Octokit::ClientError
    #   puts 'Issues are disabled for this repository.'
    end
    
    desc 'start', 'Start working on a Github issue'
    def start id
      if id.nil?
        puts 'Issue ID required.'
      else
        # Fetch issue to validate it exists
        issue = @client.issue(repo, id)
        @client.update_issue repo, issue.number, issue.title, issue.description, { assignee: @client.user.login }
        sync
        `git checkout -b issue-#{id}`
      end
    end
    
    desc 'finish', 'Finish working on a Github issue'
    def finish id = nil
      setup
      id ||= `git rev-parse --abbrev-ref HEAD`.split('-').last.to_s.chop
      if id.nil?
        puts "Unable to guess issue ID from branch name. You might want to specify it explicitly."
      else
        issue = @client.issue(repo, id)
        puts 'Pushing branch...'
        `git push -q origin issue-#{id}`
        puts "Creating pull-request for issue ##{id}..."
        @client.create_pull_request_for_issue(repo, 'master', "#{user_name}:issue-#{id}", id)
        `git checkout master`
      end
    end
    
    desc 'clone', 'Clone a Github repository'
    def clone repo
      `git clone git@github.com:#{repo}`
    end
    
    desc 'sync', 'Synchronize fork with upstream repository'
    def sync
      puts 'Synchroizing with upstream...'
      `git checkout master`
      `git fetch -q upstream`
      `git merge -q upstream/master`
    end
    
    desc 'info', 'Show current respository information'
    def info
      # debugger
      puts "Github repository: #{repo_full_name}"
      puts "Forked from: #{parent}" if parent
    end
    
    desc 'version', 'Show Gub version'
    def version
      puts Gub::VERSION
    end
    
    
    private
      def setup
        # TODO: Check if the RC file exists
        rc = File.expand_path("~/.gubrc")
        if File.exists?(rc)
          config = YAML.load_file(rc).symbolize_keys!
          @client = Octokit::Client.new access_token: config[:token]
        else
          puts 'Unable to find .gubrc file.'
          exit 1
        end
      end
    
      def table rows, header = []
        Terminal::Table.new :headings => header, :rows => rows
      end
    
      def run command, params = {}
      end
    
      def repo
        if parent
          name = parent
        else
          name = repo_full_name
        end
        name
      end
      def repo_full_name
        `git remote -v | grep origin | grep fetch | awk '{print $2}' | cut -d ':' -f 2`.to_s.chop
      end
      def repo_name
        repo_full_name.split('/').last
      end
      def user_name
        repo_full_name.split('/').first
      end
      def parent
        setup
        @client.repo(repo: repo_full_name).parent.full_name if @client.repo(repo: repo_full_name).parent
      end
    
  end  
end