root = global ? window

root.Ballots = new Meteor.Collection("ballots")

class Ballot extends ReactiveClass(Ballots)
  ballotCache = {}
  constructor: (fields) ->
    _.extend(@, fields)
    Ballot.initialize.call(@)

  # For pick mode
  isPicked: (questionIndex, choiceIndex) ->
    @depend()
    choice = @questions[questionIndex].choices[choiceIndex]
    return choice.value == true

  # toggling a pick on a choice
  pick: (questionIndex, choiceIndex) ->
    @changed()
    question = @questions[questionIndex]
    choice = question.choices[choiceIndex]
    choice.value = !choice.value
    newValue = choice.value
    # Changes if they just selected a choice
    if newValue == true
      # If it is not multiple choice, make sure all other choices are false
      if (!question.options.multi)
        _.each(question.choices, (choice, index) ->
          if index != choiceIndex
            choice.value = false
        )
      # Otherwise check if abstain is on, and if so, set it to false
      else if (question.options.allowAbstain)
        abstainChoice = question.choices[question.choices.length - 1]
        abstainChoice.value = false
    # Changes if they deselected a choice
    else
      if (question.options.allowAbstain)
        # If it's not multiple choice or nothing else is selected
        if (!question.options.multi || !_.find(question.choices, (choice) ->
          return choice.value == true
        ))
          abstainChoice = question.choices[question.choices.length - 1]
          abstainChoice.value = true
    return @

  abstain: (questionIndex) ->
    @changed()
    question = @questions[questionIndex]
    # TODO: implement rank abstain
    if (question.options.type == "pick")
      # set all choice values to false
      _.each(question.choices, (choice) ->
        choice.value = false
      )
      abstainChoice = question.choices[question.choices.length - 1]
      abstainChoice.value = true
    return @

  isAbstaining: (questionIndex) ->
    question = @questions[questionIndex]
    abstainChoice = question.choices[question.choices.length - 1]
    @depend()
    return abstainChoice.value

  @generateBallot = (election, user) ->
    if not election
      throw new Meteor.Error(500,
        "Cannot generate a ballot omit an election"
      )
    user ?= Meteor.user()
    if not user
      throw new Meteor.Error(500,
        "You must specify in a user to generate a ballot!")
    ballot = new this()
    ballot.netId = user.getNetId()
    ballot.electionId = election._id
    # Transform each question
    ballot.questions = _.map(election.questions, (question) ->
      transformedQuestion = _.omit(question,
        "description", "name", "choices")
      # Transform each choice
      transformedQuestion.choices = _.map(question.choices, (choice, index) ->
        transformedChoice = _.omit(choice,
          "description", "image", "name", "votes")
        transformedChoice.value = switch (question.options.type)
          when "pick" then false
          when "rank" then 0
          else false
        return transformedChoice
      )
      if (transformedQuestion.options.allowAbstain)
        transformedQuestion.choices.push({
          name: "abstain"
          _id: "abstain"
          value: true
        })
      return transformedQuestion
    )
    return ballot

  # Singleton to return a ballot if it exists, or create a new one if it
  # doesn't
  @getBallot = (election) ->
    if not election
      throw new Meteor.Error(500,
        "You must specify the election of the ballot you want")
    if ballotCache[election._id]
      return ballotCache[election._id]
    else
      ballotCache[election._id] = @generateBallot(election, Meteor.user())
      return ballotCache[election._id]

  # Stateful tracking of what the active ballot is
  activeBallotDep = new Deps.Dependency
  activeBallot = undefined
  @setActive = (election) ->
    if activeBallot?.electionId == election._id
      return @
    activeBallotDep.changed()
    activeBallot = @getBallot(election)
    return @

  # Reactively fetch the active ballot
  @getActive = () ->
    activeBallotDep.depend()
    if activeBallot
      activeBallot.depend()
    return activeBallot

Ballot.setupTransform()

Ballot.addOfflineFields(["random_map"])

root.Ballot = Ballot
