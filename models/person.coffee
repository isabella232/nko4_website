_ = require 'underscore'
mongoose = require 'mongoose'
auth = require 'mongoose-auth'
env = require '../config/env'

# auth decoration
PersonSchema = module.exports = new mongoose.Schema
  name: String
  email: String
  image_url: String
  location: String
  company: String
  twitter_name: String
  bio: String
  admin: Boolean
  role: { type: String, enum: ['nomination', 'contestant', 'judge', 'voter' ] }
  technical: Boolean
PersonSchema.plugin require('mongoose-types').useTimestamps
PersonSchema.plugin auth,
  everymodule:
    everyauth:
      moduleTimeout: 10000
      User: () -> Person
  github:
    everyauth:
      redirectPath: '/login/done'
      myHostname: env.hostname
      appId: env.github_app_id
      appSecret: env.secrets.github
  twitter:
    everyauth:
      redirectPath: '/login/done'
      myHostname: env.hostname
      consumerKey: env.twitter_app_id
      consumerSecret: env.secrets.twitter
      findOrCreateUser: (session, accessTok, accessTokExtra, twitter) ->
        promise = @Promise()
        Person.findOrCreateFromTwitter twitter, (err, person) ->
          return promise.fail err if err
          promise.fulfill person
        promise
  facebook:
    everyauth:
      redirectPath: '/login/done'
      myHostname: env.hostname
      appId: env.facebook_app_id
      appSecret: env.secrets.facebook

PersonSchema.virtual('login').get ->
  @github?.login or @twitter?.screen_name
PersonSchema.virtual('github_login').get -> @github?.login

PersonSchema.method 'team', (callback) ->
  Team = mongoose.model 'Team'
  Team.findOne people_ids: @id, callback

# leaves saving up to the calling code: if passing in an invite, you'll
# probably want to save both the person and the team. w/o an invite, you just
# need to save the team.
PersonSchema.method 'join', (team, invite) ->
  team.people_ids.push @id unless team.includes(this)
  if invite and old = _.detect(team.invites, (i) -> i.code == invite)
    _.extend this,
      name: @github.name
      email: old.email || @github.email
      role: 'contestant'
      company: @github.company
      location: @github.location
    team.emails = _.without team.emails, old.email
    old.remove()

PersonSchema.method 'updateFromTwitter', (twitter) ->
  @twitter = twitter
  @twitter_name = twitter.screen_name
  @name ||= twitter.name
  @location ||= twitter.location
  @bio ||= twitter.description
  @image_url ||= twitter.profile_image_url.replace('_normal.', '.')
  @role ||= 'nomination'

PersonSchema.static 'findOrCreateFromTwitter', (twitter, callback) ->
  Person.findOne { $or: [{ twitter_name: twitter.screen_name }, { 'twitter.screen_name': twitter.screen_name }]}, (error, person) ->
    return callback(error) if error
    person ||= new Person
    try person.updateFromTwitter twitter catch e then callback(e)
    person.save (err) -> callback(err, person)

Person = mongoose.model 'Person', PersonSchema
